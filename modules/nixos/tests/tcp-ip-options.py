import concurrent.futures
import socket
import sys


def check_connection(address):
    with socket.create_connection((address, 8080), timeout=3) as client:
        client.sendall(b"GET / HTTP/1.0\r\n\r\n")
        assert b"200 OK" in client.recv(4096)


def check_drop(_):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as client:
        client.settimeout(0.5)
        client.setsockopt(socket.IPPROTO_IP, socket.IP_OPTIONS, b"\x01" * 4)
        try:
            client.connect((sys.argv[1], 8080))
        except socket.timeout:
            return
        raise AssertionError("TCP connection with IPv4 options was accepted")


check_connection(sys.argv[1])
check_connection(sys.argv[2])

# Exceed the log burst to verify that the drop has no rate limit.
with concurrent.futures.ThreadPoolExecutor(max_workers=32) as pool:
    list(pool.map(check_drop, range(32)))

check_connection(sys.argv[1])
