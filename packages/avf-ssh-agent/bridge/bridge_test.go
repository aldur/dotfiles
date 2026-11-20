package main

import (
	"bytes"
	"context"
	"crypto/tls"
	"crypto/x509"
	"errors"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"time"
)

const testWait = 5 * time.Second

type bridge struct {
	*server
	t    *testing.T
	pin  string
	stop func()
}

// startBridge runs a server with short timeouts. The change function can adjust them.
func startBridge(t *testing.T, change func(*config)) *bridge {
	t.Helper()
	dir := t.TempDir()
	cfg := config{
		socket:         filepath.Join(dir, "run", "agent.sock"),
		state:          filepath.Join(dir, "state"),
		appWait:        200 * time.Millisecond,
		requestTimeout: testWait,
		pingInterval:   time.Hour,
		idleTimeout:    testWait,
		pairDeadline:   testWait,
		tokenTTL:       time.Minute,
	}
	if change != nil {
		change(&cfg)
	}
	if err := os.Mkdir(filepath.Dir(cfg.socket), 0o700); err != nil {
		t.Fatal(err)
	}
	s, err := newServer(cfg)
	if err != nil {
		t.Fatal(err)
	}
	s.cfg.port = s.tcp.Addr().(*net.TCPAddr).Port
	_, pin, err := loadIdentity(cfg.state)
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	stopped := make(chan struct{})
	go func() {
		s.run(ctx)
		close(stopped)
	}()
	b := &bridge{server: s, t: t, pin: pin, stop: func() {
		cancel()
		<-stopped
	}}
	t.Cleanup(b.stop)
	return b
}

// token runs the pair command and returns the token of the pairing line.
func (b *bridge) token() string {
	b.t.Helper()
	var out bytes.Buffer
	if err := pair(b.cfg, &out); err != nil {
		b.t.Fatal(err)
	}
	line := strings.TrimSpace(out.String())
	return line[strings.LastIndex(line, ":")+1:]
}

// fakeApp is the TLS client end. It has its own identity.
type fakeApp struct {
	t    *testing.T
	cert tls.Certificate
	conn *tls.Conn
}

func newApp(t *testing.T) *fakeApp {
	t.Helper()
	cert, _, err := loadIdentity(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	return &fakeApp{t: t, cert: cert}
}

func (a *fakeApp) tlsConfig(b *bridge) *tls.Config {
	return &tls.Config{
		Certificates:       []tls.Certificate{a.cert},
		MinVersion:         tls.VersionTLS13,
		NextProtos:         []string{alpn},
		InsecureSkipVerify: true,
		VerifyPeerCertificate: func(raw [][]byte, _ [][]*x509.Certificate) error {
			leaf, err := x509.ParseCertificate(raw[0])
			if err != nil {
				return err
			}
			if pinOf(leaf) != b.pin {
				return errors.New("wrong server pin")
			}
			return nil
		},
	}
}

func (a *fakeApp) dialWith(b *bridge, cfg *tls.Config) error {
	if a.conn != nil {
		a.conn.Close()
	}
	conn, err := tls.DialWithDialer(&net.Dialer{Timeout: testWait}, "tcp", b.tcp.Addr().String(), cfg)
	if err != nil {
		return err
	}
	conn.SetDeadline(time.Now().Add(testWait))
	a.conn = conn
	a.t.Cleanup(func() { conn.Close() })
	return nil
}

func (a *fakeApp) dial(b *bridge) {
	a.t.Helper()
	if err := a.dialWith(b, a.tlsConfig(b)); err != nil {
		a.t.Fatal(err)
	}
}

func (a *fakeApp) send(typ byte, conn uint32, payload string) {
	a.t.Helper()
	if err := writeFrame(a.conn, typ, conn, []byte(payload)); err != nil {
		a.t.Fatal(err)
	}
}

// expect reads the next frame that is not a PING and checks its type.
func (a *fakeApp) expect(typ byte) (uint32, string) {
	a.t.Helper()
	for {
		got, conn, payload, err := readFrame(a.conn)
		if err != nil {
			a.t.Fatalf("app read: %v", err)
		}
		if got == framePing && typ != framePing {
			continue
		}
		if got != typ {
			a.t.Fatalf("frame type %d, want %d", got, typ)
		}
		return conn, string(payload)
	}
}

// expectClosed checks that the bridge closes the connection.
func (a *fakeApp) expectClosed() {
	a.t.Helper()
	for {
		typ, _, _, err := readFrame(a.conn)
		if err != nil {
			var timeout net.Error
			if errors.As(err, &timeout) && timeout.Timeout() {
				a.t.Fatal("the bridge did not close the app connection")
			}
			return
		}
		if typ != framePing {
			a.t.Fatalf("frame type %d, want a closed connection", typ)
		}
	}
}

// tryPair sends PAIR and reports whether the bridge accepts it.
func (a *fakeApp) tryPair(b *bridge, token string) bool {
	a.t.Helper()
	a.dial(b)
	a.send(framePair, 0, token)
	typ, _, payload, err := readFrame(a.conn)
	if err != nil {
		return false
	}
	if typ != framePair || len(payload) != 0 {
		a.t.Fatalf("pair reply: type %d, payload %q", typ, payload)
	}
	return true
}

// pairedApp returns an app with an authenticated connection.
func pairedApp(t *testing.T, b *bridge) *fakeApp {
	t.Helper()
	a := newApp(t)
	if !a.tryPair(b, b.token()) {
		t.Fatal("pairing refused")
	}
	b.waitApp(true)
	return a
}

// waitApp waits until the bridge has, or does not have, an app connection.
func (b *bridge) waitApp(connected bool) {
	b.t.Helper()
	for end := time.Now().Add(testWait); time.Now().Before(end); time.Sleep(time.Millisecond) {
		b.mu.Lock()
		got := b.app != nil
		b.mu.Unlock()
		if got == connected {
			return
		}
	}
	b.t.Fatalf("app connected is not %v", connected)
}

type client struct {
	t *testing.T
	net.Conn
}

func (b *bridge) client() *client {
	b.t.Helper()
	c, err := net.Dial("unix", b.cfg.socket)
	if err != nil {
		b.t.Fatal(err)
	}
	c.SetDeadline(time.Now().Add(testWait))
	b.t.Cleanup(func() { c.Close() })
	return &client{b.t, c}
}

func (c *client) send(body string) {
	c.t.Helper()
	if err := writeMessage(c, []byte(body)); err != nil {
		c.t.Fatal(err)
	}
}

func (c *client) expect(want string) {
	c.t.Helper()
	got, err := readMessage(c)
	if err != nil {
		c.t.Fatalf("client read: %v", err)
	}
	if string(got) != want {
		c.t.Fatalf("client got %q, want %q", got, want)
	}
}

func (c *client) expectClosed() {
	c.t.Helper()
	if got, err := readMessage(c); err == nil {
		c.t.Fatalf("client got %q, want a closed connection", got)
	} else if timeout, ok := err.(net.Error); ok && timeout.Timeout() {
		c.t.Fatal("the bridge did not close the client connection")
	}
}

func TestPairLine(t *testing.T) {
	b := startBridge(t, nil)
	var out bytes.Buffer
	if err := pair(b.cfg, &out); err != nil {
		t.Fatal(err)
	}
	want := fmt.Sprintf(`^avf-ssh-pair:v1:%d:%s:[0-9a-f]{32}\n$`, b.cfg.port, b.pin)
	if !regexp.MustCompile(want).MatchString(out.String()) {
		t.Fatalf("pair line %q does not match %s", out.String(), want)
	}
	if len(b.pin) != 64 {
		t.Fatalf("pin %q", b.pin)
	}
	for _, name := range []string{"key.pem", "cert.pem", "pairing-token"} {
		info, err := os.Stat(filepath.Join(b.cfg.state, name))
		if err != nil {
			t.Fatal(err)
		}
		if info.Mode().Perm() != 0o600 {
			t.Errorf("%s has mode %o", name, info.Mode().Perm())
		}
	}
}

func TestPairing(t *testing.T) {
	b := startBridge(t, nil)
	token := b.token()

	if newApp(t).tryPair(b, strings.Repeat("0", 32)) {
		t.Fatal("wrong token accepted")
	}
	if newApp(t).tryPair(b, "") {
		t.Fatal("empty token accepted")
	}
	// A wrong token does not use up the good token.
	first := newApp(t)
	if !first.tryPair(b, token) {
		t.Fatal("good token refused")
	}
	if newApp(t).tryPair(b, token) {
		t.Fatal("used token accepted")
	}
	if got := pairedPin(b.cfg); len(got) != 64 {
		t.Fatalf("paired pin %q", got)
	}

	// The paired app connects again without PAIR.
	first.dial(b)
	first.send(framePing, 0, "")
	first.expect(framePong)

	// The paired app can pair again, but not with a bad token.
	if !first.tryPair(b, b.token()) {
		t.Fatal("paired app: good token refused")
	}
	if first.tryPair(b, "bad") {
		t.Fatal("paired app: bad token accepted")
	}

	// A second pairing replaces the paired pin.
	second := pairedApp(t, b)
	second.send(framePing, 0, "")
	second.expect(framePong)
	first.dial(b)
	first.send(framePing, 0, "")
	first.expectClosed()
}

func TestExpiredToken(t *testing.T) {
	b := startBridge(t, func(cfg *config) { cfg.tokenTTL = -time.Second })
	if newApp(t).tryPair(b, b.token()) {
		t.Fatal("expired token accepted")
	}
}

func TestUnpairedRefused(t *testing.T) {
	b := startBridge(t, nil)
	a := newApp(t)
	a.dial(b)
	a.send(framePing, 0, "")
	a.expectClosed()

	// A different pin stays refused after another app pairs.
	pairedApp(t, b)
	a.dial(b)
	a.send(frameMessage, 1, "x")
	a.expectClosed()
	b.waitApp(true)
}

func TestSilentUnpairedPeerDropped(t *testing.T) {
	b := startBridge(t, func(cfg *config) { cfg.pairDeadline = 100 * time.Millisecond })
	a := newApp(t)
	a.dial(b)
	a.expectClosed()
}

func TestWrongTLSRefused(t *testing.T) {
	b := startBridge(t, nil)
	a := pairedApp(t, b)

	cfg := a.tlsConfig(b)
	cfg.NextProtos = []string{"other/1"}
	if err := a.dialWith(b, cfg); err == nil {
		t.Fatal("wrong ALPN accepted")
	}

	cfg = a.tlsConfig(b)
	cfg.NextProtos = nil
	if err := a.dialWith(b, cfg); err == nil {
		a.send(framePing, 0, "")
		a.expectClosed()
	}

	cfg = a.tlsConfig(b)
	cfg.MinVersion, cfg.MaxVersion = tls.VersionTLS12, tls.VersionTLS12
	if err := a.dialWith(b, cfg); err == nil {
		t.Fatal("TLS 1.2 accepted")
	}

	cfg = a.tlsConfig(b)
	cfg.Certificates = nil
	if err := a.dialWith(b, cfg); err == nil {
		a.expectClosed()
	}
}

func TestServerPinCheck(t *testing.T) {
	b := startBridge(t, nil)
	a := newApp(t)
	cfg := a.tlsConfig(&bridge{pin: "other"})
	if err := a.dialWith(b, cfg); err == nil {
		t.Fatal("the fake app accepted a wrong server pin")
	}
}

func TestRoundTrip(t *testing.T) {
	b := startBridge(t, nil)
	a := pairedApp(t, b)
	c := b.client()

	for _, body := range []string{"\x0b", "second request"} {
		c.send(body)
		id, got := a.expect(frameMessage)
		if id != 1 || got != body {
			t.Fatalf("app got conn %d %q", id, got)
		}
		a.send(frameMessage, id, "reply to "+body)
		c.expect("reply to " + body)
	}

	// The bridge ignores a response without a request and an unknown frame type.
	a.send(frameMessage, 1, "stray")
	a.send(frameMessage, 99, "stray")
	a.send(200, 0, "unknown")
	// The PONG shows that the bridge read the frames above.
	a.send(framePing, 0, "")
	a.expect(framePong)
	c.send("third")
	a.expect(frameMessage)
	a.send(frameMessage, 1, "ok")
	c.expect("ok")

	c.Close()
	if id, _ := a.expect(frameClose); id != 1 {
		t.Fatalf("CLOSE for conn %d", id)
	}
}

func TestLargeMessage(t *testing.T) {
	b := startBridge(t, nil)
	a := pairedApp(t, b)
	c := b.client()
	body := strings.Repeat("m", maxMessage)
	c.send(body)
	id, got := a.expect(frameMessage)
	if got != body {
		t.Fatal("large message changed")
	}
	a.send(frameMessage, id, body)
	c.expect(body)

	// A message above the limit closes the client connection.
	c.Write([]byte{0, 4, 0, 1})
	c.expectClosed()
	a.expect(frameClose)
}

func TestTwoClients(t *testing.T) {
	b := startBridge(t, nil)
	a := pairedApp(t, b)
	c1, c2 := b.client(), b.client()
	c1.send("one")
	c2.send("two")

	// The app answers in the opposite order.
	ids := map[string]uint32{}
	for range 2 {
		id, body := a.expect(frameMessage)
		ids[body] = id
	}
	if ids["one"] == ids["two"] || ids["one"] == 0 || ids["two"] == 0 {
		t.Fatalf("conn ids %v", ids)
	}
	a.send(frameMessage, ids["two"], "reply two")
	a.send(frameMessage, ids["one"], "reply one")
	c1.expect("reply one")
	c2.expect("reply two")
}

func TestClientCloseWithPendingRequest(t *testing.T) {
	b := startBridge(t, nil)
	a := pairedApp(t, b)
	c := b.client()
	c.send("sign")
	id, _ := a.expect(frameMessage)
	c.Close()
	if closed, _ := a.expect(frameClose); closed != id {
		t.Fatalf("CLOSE for conn %d, want %d", closed, id)
	}
}

func TestNoApp(t *testing.T) {
	b := startBridge(t, nil)
	c := b.client()
	c.send("request")
	c.expect(string(failure))

	// The client connection stays usable.
	a := pairedApp(t, b)
	c.send("again")
	id, _ := a.expect(frameMessage)
	a.send(frameMessage, id, "reply")
	c.expect("reply")
}

func TestNoAppSharedWait(t *testing.T) {
	b := startBridge(t, func(cfg *config) { cfg.appWait = time.Second })
	c := b.client()
	c.send("first")
	c.expect(string(failure))
	start := time.Now()
	c.send("second")
	c.expect(string(failure))
	if elapsed := time.Since(start); elapsed > 500*time.Millisecond {
		t.Fatalf("the second request waited %v", elapsed)
	}
}

func TestRequestWaitsForApp(t *testing.T) {
	b := startBridge(t, func(cfg *config) { cfg.appWait = testWait })
	a := newApp(t)
	token := b.token()
	c := b.client()
	c.send("early")
	if !a.tryPair(b, token) {
		t.Fatal("pairing refused")
	}
	id, _ := a.expect(frameMessage)
	a.send(frameMessage, id, "reply")
	c.expect("reply")
}

func TestRequestTimeout(t *testing.T) {
	b := startBridge(t, func(cfg *config) { cfg.requestTimeout = 100 * time.Millisecond })
	a := pairedApp(t, b)
	c := b.client()
	c.send("slow")
	id, _ := a.expect(frameMessage)
	c.expect(string(failure))
	c.expectClosed()
	if closed, _ := a.expect(frameClose); closed != id {
		t.Fatalf("CLOSE for conn %d, want %d", closed, id)
	}
}

func TestAppDrop(t *testing.T) {
	b := startBridge(t, nil)
	a := pairedApp(t, b)
	pending, idle, unused := b.client(), b.client(), b.client()
	idle.send("first")
	id, _ := a.expect(frameMessage)
	a.send(frameMessage, id, "reply")
	idle.expect("reply")
	pending.send("sign")
	a.expect(frameMessage)

	a.conn.Close()
	pending.expect(string(failure))
	pending.expectClosed()
	idle.expectClosed()
	b.waitApp(false)

	// A client that did not use the dropped connection stays usable.
	a.dial(b)
	b.waitApp(true)
	unused.send("request")
	id, _ = a.expect(frameMessage)
	a.send(frameMessage, id, "reply")
	unused.expect("reply")
}

func TestAppReplaced(t *testing.T) {
	b := startBridge(t, nil)
	old := pairedApp(t, b)
	c := b.client()
	c.send("sign")
	old.expect(frameMessage)

	replacement := &fakeApp{t: t, cert: old.cert}
	replacement.dial(b)
	replacement.send(framePing, 0, "")
	replacement.expect(framePong)
	old.expectClosed()
	c.expect(string(failure))
	c.expectClosed()

	next := b.client()
	next.send("request")
	id, body := replacement.expect(frameMessage)
	if id != 2 || body != "request" {
		t.Fatalf("app got conn %d %q", id, body)
	}
	replacement.send(frameMessage, id, "reply")
	next.expect("reply")
}

func TestIdleTimeout(t *testing.T) {
	b := startBridge(t, func(cfg *config) { cfg.idleTimeout = 150 * time.Millisecond })
	a := pairedApp(t, b)
	a.expectClosed()
	b.waitApp(false)
}

func TestKeepalive(t *testing.T) {
	b := startBridge(t, func(cfg *config) {
		cfg.pingInterval = 20 * time.Millisecond
		cfg.idleTimeout = 200 * time.Millisecond
	})
	a := pairedApp(t, b)
	// The PONG replies keep the connection open for longer than the idle timeout.
	for end := time.Now().Add(500 * time.Millisecond); time.Now().Before(end); {
		a.expect(framePing)
		a.send(framePong, 0, "")
	}
	a.send(framePing, 0, "")
	a.expect(framePong)
}

func TestOversizeFrameDropsApp(t *testing.T) {
	b := startBridge(t, nil)
	a := pairedApp(t, b)
	a.conn.Write([]byte{0, 4, 0, 6, frameMessage, 0, 0, 0, 1})
	a.expectClosed()
	b.waitApp(false)
}

func TestStatus(t *testing.T) {
	b := startBridge(t, nil)
	read := func() string {
		var out bytes.Buffer
		if err := status(b.cfg, &out); err != nil {
			t.Fatal(err)
		}
		return out.String()
	}
	if got, want := read(), "paired: no\napp: not connected\nlast error: none\n"; got != want {
		t.Fatalf("status %q, want %q", got, want)
	}

	pairedApp(t, b)
	if got := read(); !regexp.MustCompile(`^paired: yes\napp: connected since \S+\nlast error: none\n$`).MatchString(got) {
		t.Fatalf("status %q", got)
	}

	b.mu.Lock()
	b.app.conn.Close()
	b.mu.Unlock()
	b.waitApp(false)
	c := b.client()
	c.send("request")
	c.expect(string(failure))
	if got := read(); !regexp.MustCompile(`^paired: yes\napp: not connected\nlast error: \S+ no app connected: .*\n$`).MatchString(got) {
		t.Fatalf("status %q", got)
	}

	info, err := os.Stat(b.cfg.socket)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Errorf("socket has mode %o", info.Mode().Perm())
	}

	b.stop()
	if got, want := read(), "paired: yes\nthe bridge does not run\n"; got != want {
		t.Fatalf("status %q, want %q", got, want)
	}
	if _, err := os.Stat(b.cfg.socket); !errors.Is(err, os.ErrNotExist) {
		t.Errorf("the socket file stays after the stop: %v", err)
	}
}

func TestStaleSocketRemoved(t *testing.T) {
	b := startBridge(t, nil)
	stale, err := os.Create(filepath.Join(t.TempDir(), "agent.sock"))
	if err != nil {
		t.Fatal(err)
	}
	stale.Close()
	cfg := b.cfg
	cfg.port, cfg.socket = 0, stale.Name()
	s, err := newServer(cfg)
	if err != nil {
		t.Fatal(err)
	}
	s.tcp.Close()
	s.unix.Close()
}
