// Command avf-ssh-agent serves an ssh-agent socket and sends each request
// to an app that connects with mutual TLS.
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"io/fs"
	"log"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"
)

type config struct {
	port   int
	socket string
	state  string

	appWait        time.Duration
	requestTimeout time.Duration
	pingInterval   time.Duration
	idleTimeout    time.Duration
	pairDeadline   time.Duration
	tokenTTL       time.Duration
}

func statusPath(cfg config) string { return filepath.Join(filepath.Dir(cfg.socket), "status") }

func usage() {
	fmt.Fprintln(os.Stderr, "usage: avf-ssh-agent serve|pair|status [flags]")
	os.Exit(2)
}

func main() {
	log.SetFlags(0)
	if len(os.Args) < 2 {
		usage()
	}
	var cfg config
	flags := flag.NewFlagSet(os.Args[1], flag.ExitOnError)
	flags.IntVar(&cfg.port, "port", 25970, "TCP port on 127.0.0.1 for the app")
	flags.StringVar(&cfg.socket, "socket", "/run/avf-ssh-agent/agent.sock", "ssh-agent Unix socket")
	flags.StringVar(&cfg.state, "state", "/var/lib/avf-ssh-agent", "state directory")

	var run func() error
	switch os.Args[1] {
	case "serve":
		flags.DurationVar(&cfg.appWait, "app-wait", 15*time.Second, "time that a request waits for the app to connect")
		flags.DurationVar(&cfg.requestTimeout, "request-timeout", 120*time.Second, "time that a request waits for the response")
		flags.DurationVar(&cfg.pingInterval, "ping-interval", 30*time.Second, "interval between PING frames")
		flags.DurationVar(&cfg.idleTimeout, "idle-timeout", 75*time.Second, "time without a frame before the app connection drops")
		flags.DurationVar(&cfg.pairDeadline, "pair-deadline", 5*time.Second, "time for the handshake and the first frame of an unpaired peer")
		run = func() error {
			ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
			defer stop()
			s, err := newServer(cfg)
			if err != nil {
				return err
			}
			s.run(ctx)
			return nil
		}
	case "pair":
		flags.DurationVar(&cfg.tokenTTL, "token-ttl", 300*time.Second, "life of the pairing token")
		run = func() error { return pair(cfg, os.Stdout) }
	case "status":
		run = func() error { return status(cfg, os.Stdout) }
	default:
		usage()
	}
	flags.Parse(os.Args[2:])
	if flags.NArg() > 0 {
		usage()
	}
	if err := run(); err != nil {
		log.Fatal(err)
	}
}

// status prints the pairing state and the status file of the daemon.
func status(cfg config, out io.Writer) error {
	paired := "no"
	if pairedPin(cfg) != "" {
		paired = "yes"
	}
	fmt.Fprintf(out, "paired: %s\n", paired)
	text, err := os.ReadFile(statusPath(cfg))
	if errors.Is(err, fs.ErrNotExist) {
		text, err = []byte("the bridge does not run\n"), nil
	}
	if err != nil {
		return err
	}
	_, err = out.Write(text)
	return err
}
