package main

import (
	"context"
	"crypto/tls"
	"errors"
	"fmt"
	"log"
	"net"
	"os"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
)

type server struct {
	cfg  config
	tls  *tls.Config
	unix net.Listener
	tcp  net.Listener

	lastID atomic.Uint32

	mu        sync.Mutex
	app       *appConn      // The authenticated app connection, or nil.
	ready     chan struct{} // Closed while app is not nil.
	since     time.Time
	waitUntil time.Time // The end of the current wait for an app connection.
	stopped   bool
	lastError string
}

// appConn is one authenticated TLS connection from the app.
type appConn struct {
	conn    *tls.Conn
	timeout time.Duration
	writeMu sync.Mutex
	done    chan struct{} // Closed when the connection drops.

	// The server lock guards these maps. The key is the client connection id.
	pending map[uint32]chan []byte // Requests that wait for a response.
	clients map[uint32]net.Conn    // Clients that sent a MESSAGE on this connection.
}

func (a *appConn) send(typ byte, conn uint32, payload []byte) {
	a.writeMu.Lock()
	defer a.writeMu.Unlock()
	a.conn.SetWriteDeadline(time.Now().Add(a.timeout))
	if writeFrame(a.conn, typ, conn, payload) != nil {
		// The read loop gets an error and drops the connection.
		a.conn.Close()
	}
}

func newServer(cfg config) (*server, error) {
	cert, _, err := loadIdentity(cfg.state)
	if err != nil {
		return nil, err
	}
	s := &server{cfg: cfg, tls: serverTLS(cert), ready: make(chan struct{}), lastError: "none"}
	if s.tcp, err = net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", cfg.port)); err != nil {
		return nil, err
	}
	if err := os.Remove(cfg.socket); err != nil && !errors.Is(err, os.ErrNotExist) {
		return nil, err
	}
	// The umask makes sure that the socket is never open to other users.
	umask := syscall.Umask(0o177)
	s.unix, err = net.Listen("unix", cfg.socket)
	syscall.Umask(umask)
	if err != nil {
		s.tcp.Close()
		return nil, err
	}
	s.mu.Lock()
	s.writeStatus()
	s.mu.Unlock()
	return s, nil
}

// run serves until ctx is done. Then it removes the socket and the status file.
func (s *server) run(ctx context.Context) {
	go acceptLoop(s.unix, s.handleClient)
	go acceptLoop(s.tcp, s.handleApp)
	log.Printf("listening on %s and %s", s.unix.Addr(), s.tcp.Addr())
	<-ctx.Done()
	s.tcp.Close()
	s.unix.Close()
	s.mu.Lock()
	defer s.mu.Unlock()
	s.stopped = true
	os.Remove(statusPath(s.cfg))
}

func acceptLoop(l net.Listener, handle func(net.Conn)) {
	for {
		c, err := l.Accept()
		if errors.Is(err, net.ErrClosed) {
			return
		}
		if err != nil {
			log.Fatalf("accept on %s: %v", l.Addr(), err)
		}
		go handle(c)
	}
}

// fail logs an error and records it for the status command.
func (s *server) fail(format string, args ...any) {
	msg := fmt.Sprintf(format, args...)
	log.Print(msg)
	s.mu.Lock()
	defer s.mu.Unlock()
	s.lastError = time.Now().Format(time.RFC3339) + " " + msg
	s.writeStatus()
}

// writeStatus rewrites the status file. The caller holds the lock.
func (s *server) writeStatus() {
	if s.stopped {
		return
	}
	app := "not connected"
	if s.app != nil {
		app = "connected since " + s.since.Format(time.RFC3339)
	}
	text := fmt.Sprintf("app: %s\nlast error: %s\n", app, s.lastError)
	// The rename makes sure that a reader never gets a partial file.
	tmp := statusPath(s.cfg) + ".tmp"
	err := os.WriteFile(tmp, []byte(text), 0o600)
	if err == nil {
		err = os.Rename(tmp, statusPath(s.cfg))
	}
	if err != nil {
		log.Printf("status file: %v", err)
	}
}

func (s *server) handleApp(c net.Conn) {
	conn := tls.Server(c, s.tls)
	defer conn.Close()
	peer := c.RemoteAddr()

	conn.SetDeadline(time.Now().Add(s.cfg.pairDeadline))
	if err := conn.Handshake(); err != nil {
		s.fail("refused peer %s: TLS handshake: %v", peer, err)
		return
	}
	state := conn.ConnectionState()
	if state.NegotiatedProtocol != alpn {
		s.fail("refused peer %s: ALPN is not %s", peer, alpn)
		return
	}
	pin := pinOf(state.PeerCertificates[0])
	if pin != pairedPin(s.cfg) {
		typ, _, token, err := readFrame(conn)
		if err != nil || typ != framePair {
			s.fail("refused peer %s: pin %s is not paired", peer, pin)
			return
		}
		if !s.pair(peer, pin, token) || writeFrame(conn, framePair, 0, nil) != nil {
			return
		}
	}
	conn.SetDeadline(time.Time{})

	a := &appConn{
		conn:    conn,
		timeout: s.cfg.idleTimeout,
		done:    make(chan struct{}),
		pending: make(map[uint32]chan []byte),
		clients: make(map[uint32]net.Conn),
	}
	s.attach(a)
	defer s.drop(a)
	go func() {
		ping := time.NewTicker(s.cfg.pingInterval)
		defer ping.Stop()
		for {
			select {
			case <-ping.C:
				a.send(framePing, 0, nil)
			case <-a.done:
				return
			}
		}
	}()

	for {
		conn.SetReadDeadline(time.Now().Add(s.cfg.idleTimeout))
		typ, id, payload, err := readFrame(conn)
		if err != nil {
			log.Printf("app %s: read: %v", peer, err)
			return
		}
		switch typ {
		case frameMessage:
			s.mu.Lock()
			response := a.pending[id]
			delete(a.pending, id)
			s.mu.Unlock()
			if response != nil {
				response <- payload
			}
		case framePing:
			a.send(framePong, 0, nil)
		case framePair:
			// The paired app can pair again, for example after it lost its record of the bridge.
			if !s.pair(peer, pin, payload) {
				return
			}
			a.send(framePair, 0, nil)
		}
	}
}

// pair uses the token to make pin the paired pin. It returns false on refusal.
func (s *server) pair(peer net.Addr, pin string, token []byte) bool {
	s.mu.Lock()
	err := acceptPair(s.cfg, pin, token)
	s.mu.Unlock()
	if err != nil {
		s.fail("refused peer %s: pairing refused: %v", peer, err)
		return false
	}
	log.Printf("pairing accepted: peer %s, pin %s", peer, pin)
	return true
}

// attach makes a the current app connection and drops the old one.
func (s *server) attach(a *appConn) {
	s.mu.Lock()
	old := s.app
	s.app, s.since, s.waitUntil = a, time.Now(), time.Time{}
	if old == nil {
		close(s.ready)
		log.Printf("app connected: %s", a.conn.RemoteAddr())
	} else {
		log.Printf("app connected: %s replaces %s", a.conn.RemoteAddr(), old.conn.RemoteAddr())
	}
	s.writeStatus()
	s.mu.Unlock()
	if old != nil {
		s.drop(old)
	}
}

// drop closes a and the client connections that used it.
// The app keeps the state of a client connection for one TLS connection only.
func (s *server) drop(a *appConn) {
	s.mu.Lock()
	defer s.mu.Unlock()
	select {
	case <-a.done:
		return
	default:
	}
	close(a.done)
	a.conn.Close()
	log.Printf("app disconnected: %s", a.conn.RemoteAddr())
	for id, c := range a.clients {
		// The handler of a pending request sends the failure reply and then closes.
		if _, pending := a.pending[id]; !pending {
			c.Close()
		}
	}
	if s.app == a {
		s.app = nil
		s.ready = make(chan struct{})
		s.writeStatus()
	}
}

// acquire registers a request of client id on the current app connection.
// It waits for an app connection if there is none, and returns nil on timeout.
// A client that used a different app connection gets nil immediately.
func (s *server) acquire(id uint32, c net.Conn, used *appConn) (*appConn, chan []byte) {
	var timeout <-chan time.Time
	for {
		s.mu.Lock()
		a, ready := s.app, s.ready
		if used != nil && a != used {
			s.mu.Unlock()
			return nil, nil
		}
		if a != nil {
			response := make(chan []byte, 1)
			a.pending[id] = response
			a.clients[id] = c
			s.mu.Unlock()
			return a, response
		}
		if timeout == nil {
			// One ssh command sends some requests in sequence. All of them
			// share one wait, so the command fails after appWait in total.
			now := time.Now()
			if now.After(s.waitUntil.Add(s.cfg.appWait)) {
				s.waitUntil = now.Add(s.cfg.appWait)
			}
			timeout = time.After(time.Until(s.waitUntil))
		}
		s.mu.Unlock()
		select {
		case <-ready:
		case <-timeout:
			return nil, nil
		}
	}
}

func (s *server) handleClient(c net.Conn) {
	defer c.Close()
	id := s.lastID.Add(1)

	// A separate reader lets the handler see a client close while a request is pending.
	requests := make(chan []byte)
	done := make(chan struct{})
	defer close(done)
	go func() {
		defer close(requests)
		for {
			body, err := readMessage(c)
			if err != nil {
				return
			}
			select {
			case requests <- body:
			case <-done:
				return
			}
		}
	}()

	var used *appConn
	defer func() {
		if used == nil {
			return
		}
		s.mu.Lock()
		delete(used.pending, id)
		delete(used.clients, id)
		s.mu.Unlock()
		used.send(frameClose, id, nil)
	}()

	for body := range requests {
		a, response := s.acquire(id, c, used)
		if a == nil {
			if used != nil {
				return
			}
			s.fail("no app connected: request of client %d fails", id)
			if writeMessage(c, failure) != nil {
				return
			}
			continue
		}
		used = a
		a.send(frameMessage, id, body)
		select {
		case body := <-response:
			if writeMessage(c, body) != nil {
				return
			}
		case <-a.done:
			writeMessage(c, failure)
			return
		case <-time.After(s.cfg.requestTimeout):
			s.fail("request timeout: client %d", id)
			writeMessage(c, failure)
			return
		case <-requests:
			// The client closed, or it sent a request before the response.
			return
		}
	}
}
