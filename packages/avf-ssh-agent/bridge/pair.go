package main

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

func tokenPath(cfg config) string     { return filepath.Join(cfg.state, "pairing-token") }
func pairedPinPath(cfg config) string { return filepath.Join(cfg.state, "paired-pin") }

// pair makes a one-time token and prints the pairing line.
func pair(cfg config, out io.Writer) error {
	_, pin, err := loadIdentity(cfg.state)
	if err != nil {
		return err
	}
	raw := make([]byte, 16)
	if _, err := rand.Read(raw); err != nil {
		return err
	}
	token := hex.EncodeToString(raw)
	expiry := time.Now().Add(cfg.tokenTTL).Unix()
	if err := os.WriteFile(tokenPath(cfg), fmt.Appendf(nil, "%s\n%d\n", token, expiry), 0o600); err != nil {
		return err
	}
	_, err = fmt.Fprintf(out, "avf-ssh-pair:v1:%d:%s:%s\n", cfg.port, pin, token)
	return err
}

func pairedPin(cfg config) string {
	data, _ := os.ReadFile(pairedPinPath(cfg))
	return strings.TrimSpace(string(data))
}

// acceptPair uses the token and stores pin as the paired pin.
// The caller holds the lock, thus one token cannot pair two peers.
func acceptPair(cfg config, pin string, token []byte) error {
	data, err := os.ReadFile(tokenPath(cfg))
	if err != nil {
		return errors.New("no pairing token")
	}
	want, expiry, _ := strings.Cut(strings.TrimSpace(string(data)), "\n")
	deadline, err := strconv.ParseInt(expiry, 10, 64)
	if err != nil || want == "" {
		return errors.New("bad pairing token file")
	}
	if time.Now().Unix() >= deadline {
		return errors.New("expired token")
	}
	if subtle.ConstantTimeCompare([]byte(want), token) != 1 {
		return errors.New("wrong token")
	}
	if err := os.Remove(tokenPath(cfg)); err != nil {
		return err
	}
	return os.WriteFile(pairedPinPath(cfg), []byte(pin+"\n"), 0o600)
}
