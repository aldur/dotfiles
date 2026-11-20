package main

import (
	"encoding/binary"
	"fmt"
	"io"
)

const (
	frameMessage = 1
	frameClose   = 2
	framePing    = 3
	framePong    = 4
	framePair    = 5

	maxMessage = 262144
)

// The reply SSH_AGENT_FAILURE, without its length prefix.
var failure = []byte{5}

func writeFrame(w io.Writer, typ byte, conn uint32, payload []byte) error {
	b := make([]byte, 9, 9+len(payload))
	binary.BigEndian.PutUint32(b, uint32(5+len(payload)))
	b[4] = typ
	binary.BigEndian.PutUint32(b[5:], conn)
	// One Write call keeps the frame in one TLS record when possible.
	_, err := w.Write(append(b, payload...))
	return err
}

func readFrame(r io.Reader) (typ byte, conn uint32, payload []byte, err error) {
	var h [9]byte
	if _, err = io.ReadFull(r, h[:]); err != nil {
		return
	}
	n := binary.BigEndian.Uint32(h[:])
	if n < 5 || n > maxMessage+5 {
		err = fmt.Errorf("bad frame length %d", n)
		return
	}
	payload = make([]byte, n-5)
	_, err = io.ReadFull(r, payload)
	return h[4], binary.BigEndian.Uint32(h[5:]), payload, err
}

// writeMessage writes one ssh-agent message with its length prefix.
func writeMessage(w io.Writer, body []byte) error {
	b := binary.BigEndian.AppendUint32(make([]byte, 0, 4+len(body)), uint32(len(body)))
	_, err := w.Write(append(b, body...))
	return err
}

// readMessage reads one ssh-agent message and returns it without its length prefix.
func readMessage(r io.Reader) ([]byte, error) {
	var h [4]byte
	if _, err := io.ReadFull(r, h[:]); err != nil {
		return nil, err
	}
	n := binary.BigEndian.Uint32(h[:])
	if n < 1 || n > maxMessage {
		return nil, fmt.Errorf("bad message length %d", n)
	}
	body := make([]byte, n)
	_, err := io.ReadFull(r, body)
	return body, err
}
