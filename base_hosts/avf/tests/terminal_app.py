"""A stand-in for the Android side of the Terminal app, for the boot check.

It talks to the real guest agent (linux_vm_manager) through vhost-device-vsock
as the app does: the binder RPC protocol of libbinder (RpcWireFormat.h,
RpcState.cpp and RpcSession.cpp in frameworks/native/libs/binder), and the
AIDL interfaces IVirtualMachineService, IGuestAgent, IDebianService and
IVmActivePortListener in packages/modules/Virtualization. It uses the terminal
of the app (ttyd through vsock port 7681) to act as the user in the guest.

Usage: terminal_app.py UDS_PATH GUEST_CID

The guest must already be starting. Each check writes one line "APP NAME ok"
or "APP NAME FAIL: DETAIL". The last line is "APP done failures=N".
"""

import base64
import json
import os
import queue
import re
import socket
import struct
import sys
import threading
import time

UDS, GUEST_CID = sys.argv[1], int(sys.argv[2])
START = time.monotonic()

# RpcWireFormat.h
COMMAND_TRANSACT, COMMAND_REPLY, COMMAND_DEC_STRONG = 0, 1, 2
SPECIAL_GET_ROOT, SPECIAL_GET_MAX_THREADS, SPECIAL_GET_SESSION_ID = 0, 1, 2
OPTION_INCOMING = 1
ADDRESS_CREATED, ADDRESS_FOR_SERVER = 1, 2
CONNECTION_INIT = b"cci\0" + bytes(4)
FLAG_ONEWAY = 1
PROTOCOL_VERSION = 2
UNKNOWN_TRANSACTION = -74
# IBinder.h: libbinder asks an object for its descriptor with this code.
INTERFACE_TRANSACTION = 0x5F4E5446
# A transaction code is FIRST_CALL_TRANSACTION (1) plus the AIDL ID. The
# methods without an ID have the IDs 0, 1, 2 and so on.
REGISTER_GUEST_AGENT = 2
SHUTDOWN_ASYNC = 2
STABILITY_VINTF = 0b111111

VM_SERVICE = "android.system.virtualmachineservice.IVirtualMachineService"
GUEST_AGENT = "android.system.virtualizationcommon.IGuestAgent"
DEBIAN_SERVICE = "com.android.virtualization.debian.aidl.IDebianService"
PORT_LISTENER = "com.android.virtualization.debian.aidl.IVmActivePortListener"
DEBIAN_SERVICE_PORT = 4000
TTYD_PORT = 7681


def address(number, for_server):
    options = ADDRESS_CREATED | (ADDRESS_FOR_SERVER if for_server else 0)
    return options | number << 32


class Parcel:
    """A parcel in the RPC format: 4-byte aligned, with binder positions."""

    def __init__(self, data=b"", positions=()):
        self.data = bytearray(data)
        self.positions = list(positions)
        self.offset = 0

    def _pad(self):
        self.data += bytes(-len(self.data) % 4)

    def int32(self, value):
        self.data += struct.pack("<i", value)
        return self

    def int64(self, value):
        self.data += struct.pack("<q", value)
        return self

    def string16(self, text):
        encoded = text.encode("utf-16-le")
        self.int32(len(encoded) // 2)
        self.data += encoded + b"\0\0"
        self._pad()
        return self

    def binder(self, raw_address):
        self.positions.append(len(self.data))
        self.int32(1)
        self.data += struct.pack("<Q", raw_address)
        return self.int32(STABILITY_VINTF)

    def read(self, size):
        chunk = bytes(self.data[self.offset : self.offset + size])
        if len(chunk) != size:
            raise ValueError("parcel too short")
        self.offset += size
        return chunk

    def read_int32(self):
        return struct.unpack("<i", self.read(4))[0]

    def read_string16(self):
        length = self.read_int32()
        if length < 0:
            return None
        text = self.read(2 * length).decode("utf-16-le")
        self.read(2 + (-(2 * length + 2) % 4))
        return text

    def read_binder(self):
        if self.read_int32() != 1:
            return None
        raw = struct.unpack("<Q", self.read(8))[0]
        self.read_int32()  # stability
        return raw

    def read_bytes(self):
        length = self.read_int32()
        chunk = self.read(length)
        self.read(-length % 4)
        return chunk


def interface(descriptor):
    return Parcel().string16(descriptor)


def vsock_connect(port, timeout=60):
    """Connect to PORT of the guest through vhost-device-vsock."""
    deadline = time.monotonic() + timeout
    while True:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            sock.connect(UDS)
            sock.sendall(f"CONNECT {port}\n".encode())
            line = b""
            while not line.endswith(b"\n"):
                byte = sock.recv(1)
                if not byte:
                    raise ConnectionError("closed")
                line += byte
            if line.startswith(b"OK"):
                return sock
        except OSError:
            pass
        sock.close()
        if time.monotonic() > deadline:
            raise TimeoutError(f"vsock port {port} of the guest")
        time.sleep(0.2)


def vsock_listen(port):
    """Listen on PORT of the host. The guest connects to CID 2, port PORT."""
    path = f"{UDS}_{port}"
    if os.path.exists(path):
        os.unlink(path)
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(path)
    server.listen()
    return server


class Connection:
    """One RPC connection. Calls HANDLER for each transaction that comes in."""

    def __init__(
        self, sock, version, handler=lambda target, code, parcel: (UNKNOWN_TRANSACTION, None)
    ):
        self.sock, self.version, self.handler = sock, version, handler
        self.lock = threading.Lock()

    def recv(self, size):
        data = b""
        while len(data) < size:
            chunk = self.sock.recv(size - len(data))
            if not chunk:
                raise ConnectionError("connection closed")
            data += chunk
        return data

    def send(self, command, body):
        with self.lock:
            self.sock.sendall(struct.pack("<IIII", command, len(body), 0, 0) + body)

    def table(self, parcel):
        if self.version < 2:
            return b""
        return b"".join(struct.pack("<I", p) for p in parcel.positions)

    def split(self, body, size):
        data, rest = body[:size], body[size:]
        positions = struct.unpack(f"<{len(rest) // 4}I", rest) if self.version >= 2 else ()
        return Parcel(data, positions)

    def _transact(self, target, code, parcel, flags, async_number):
        body = struct.pack("<QIIQI12x", target, code, flags, async_number, len(parcel.data))
        self.send(COMMAND_TRANSACT, body + bytes(parcel.data) + self.table(parcel))

    def send_oneway(self, target, code, parcel, async_number=0):
        self._transact(target, code, parcel, FLAG_ONEWAY, async_number)

    def call(self, target, code, parcel):
        self._transact(target, code, parcel, 0, 0)
        while True:
            command, body = self.next_command()
            if command == COMMAND_REPLY:
                status, size = struct.unpack("<iI", body[:8])
                if status != 0:
                    raise RuntimeError(f"transaction {code} returned status {status}")
                return self.split(body[20:], size)
            self.dispatch(command, body)

    def next_command(self):
        command, size = struct.unpack("<II8x", self.recv(16))
        return command, self.recv(size)

    def dispatch(self, command, body):
        if command != COMMAND_TRANSACT:
            return  # COMMAND_DEC_STRONG: the stand-in keeps all objects.
        target, code, flags, _, size = struct.unpack("<QIIQI12x", body[:40])
        status, reply = self.handler(target, code, self.split(body[40:], size))
        if not flags & FLAG_ONEWAY:
            reply = reply or Parcel()
            self.send(
                COMMAND_REPLY,
                struct.pack("<iI12x", status, len(reply.data))
                + bytes(reply.data)
                + self.table(reply),
            )

    def serve(self):
        try:
            while True:
                self.dispatch(*self.next_command())
        except (ConnectionError, OSError):
            pass


def connection_header(session_id=b"", incoming=False):
    options = OPTION_INCOMING if incoming else 0
    return struct.pack("<IBB8xH", PROTOCOL_VERSION, options, 0, len(session_id)) + session_id


class VirtualMachineService:
    """The RPC server of the host. The agent registers its IGuestAgent here."""

    ROOT = address(1, for_server=True)

    def __init__(self):
        self.sessions = {}
        self.guest_agent = queue.Queue()
        self.listener = vsock_listen(GUEST_CID)
        threading.Thread(target=self.accept, daemon=True).start()

    def accept(self):
        while True:
            sock, _ = self.listener.accept()
            threading.Thread(target=self.establish, args=(sock,), daemon=True).start()

    def establish(self, sock):
        connection = Connection(sock, PROTOCOL_VERSION)
        version, options, _, id_size = struct.unpack("<IBB8xH", connection.recv(16))
        session_id = connection.recv(id_size)
        if not session_id:
            session_id = os.urandom(32)
            version = min(version, PROTOCOL_VERSION)
            self.sessions[session_id] = {"version": version}
            sock.sendall(struct.pack("<I4x", version))
        session = self.sessions[session_id]
        connection.version = session["version"]
        connection.handler = lambda t, c, p: self.handle(session_id, t, c, p)
        if options & OPTION_INCOMING:
            # The agent serves its objects on this connection.
            sock.sendall(CONNECTION_INIT)
            session["agent"] = connection
            return
        if connection.recv(8) != CONNECTION_INIT:
            raise ConnectionError("no connection init")
        connection.serve()

    def handle(self, session_id, target, code, parcel):
        if target == 0:
            if code == SPECIAL_GET_ROOT:
                return 0, Parcel().binder(self.ROOT)
            if code == SPECIAL_GET_MAX_THREADS:
                return 0, Parcel().int32(1)
            if code == SPECIAL_GET_SESSION_ID:
                reply = Parcel().int32(len(session_id))
                reply.data += session_id
                return 0, reply
        if target == self.ROOT and code == INTERFACE_TRANSACTION:
            return 0, Parcel().string16(VM_SERVICE)
        if target == self.ROOT and code == REGISTER_GUEST_AGENT:
            if parcel.read_string16() != VM_SERVICE:
                return UNKNOWN_TRANSACTION, None
            self.guest_agent.put((session_id, parcel.read_binder()))
            return 0, Parcel().int32(0)
        return UNKNOWN_TRANSACTION, None

    def shutdown_guest(self, session_id, guest_agent):
        connection = self.sessions[session_id]["agent"]
        connection.send_oneway(guest_agent, SHUTDOWN_ASYNC, interface(GUEST_AGENT))


class DebianService:
    """The RPC client of the app for IDebianService on vsock port 4000."""

    LISTENER = address(1, for_server=False)

    def __init__(self):
        self.ports = queue.Queue()
        self.report_times = []
        sock = vsock_connect(DEBIAN_SERVICE_PORT)
        sock.sendall(connection_header() + CONNECTION_INIT)
        version = struct.unpack("<I4x", Connection(sock, 0).recv(8))[0]
        self.connection = Connection(sock, version, self.handle)
        self.connection.call(0, SPECIAL_GET_MAX_THREADS, Parcel())
        session_id = self.connection.call(0, SPECIAL_GET_SESSION_ID, Parcel()).read_bytes()
        # A connection on which the agent calls the port listener.
        incoming = vsock_connect(DEBIAN_SERVICE_PORT)
        incoming.sendall(connection_header(session_id, incoming=True))
        callbacks = Connection(incoming, version, self.handle)
        if callbacks.recv(8) != CONNECTION_INIT:
            raise ConnectionError("no connection init")
        threading.Thread(target=callbacks.serve, daemon=True).start()
        self.root = self.connection.call(0, SPECIAL_GET_ROOT, Parcel()).read_binder()
        self.async_number = 0

    def handle(self, target, code, parcel):
        if target == self.LISTENER and code == INTERFACE_TRANSACTION:
            return 0, Parcel().string16(PORT_LISTENER)
        if target == self.LISTENER and code == 1:  # reportActivePorts
            parcel.read_string16()
            ports = {}
            for _ in range(parcel.read_int32()):
                parcel.read_int32()  # not null
                start, size = parcel.offset, parcel.read_int32()
                port, comm = parcel.read_int32(), parcel.read_string16()
                parcel.offset = start + size
                ports[port] = comm
            self.report_times.append(time.monotonic())
            self.ports.put(ports)
        return 0, None

    def oneway(self, code, parcel):
        self.connection.send_oneway(self.root, code, parcel, self.async_number)
        self.async_number += 1

    def set_port_listener(self):
        self.oneway(1, interface(DEBIAN_SERVICE).binder(self.LISTENER))

    def request_forwarding(self, guest_port, vsock_port):
        self.oneway(2, interface(DEBIAN_SERVICE).int32(guest_port).int32(vsock_port))

    def request_storage_balloon(self, available_bytes):
        self.oneway(3, interface(DEBIAN_SERVICE).int64(available_bytes))

    def update_clipboard(self, text):
        self.oneway(4, interface(DEBIAN_SERVICE).string16(text))

    def read_clipboard(self):
        reply = self.connection.call(self.root, 5, interface(DEBIAN_SERVICE))
        if reply.read_int32() != 0:
            raise RuntimeError("readClipboard threw an exception")
        return reply.read_string16()


class Terminal:
    """The terminal of the app: ttyd over a WebSocket through vsock 7681."""

    def __init__(self):
        self.sock = vsock_connect(TTYD_PORT)
        key = base64.b64encode(os.urandom(16)).decode()
        self.sock.sendall(
            "GET /ws HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\n"
            f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\n"
            "Sec-WebSocket-Version: 13\r\nSec-WebSocket-Protocol: tty\r\n\r\n".encode()
        )
        response = b""
        while b"\r\n\r\n" not in response:
            chunk = self.sock.recv(1)
            if not chunk:
                raise ConnectionError("ttyd closed the connection")
            response += chunk
        if b" 101 " not in response.split(b"\r\n")[0]:
            raise ConnectionError(response.split(b"\r\n")[0].decode())
        self.output = b""
        self.changed = threading.Condition()
        threading.Thread(target=self.read, daemon=True).start()
        self.frame(1, json.dumps({"AuthToken": "", "columns": 200, "rows": 50}).encode())

    def frame(self, opcode, payload):
        mask = os.urandom(4)
        length = len(payload)
        if length < 126:
            header = struct.pack("!BB", 0x80 | opcode, 0x80 | length)
        else:
            header = struct.pack("!BBH", 0x80 | opcode, 0x80 | 126, length)
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        self.sock.sendall(header + mask + masked)

    def read(self):
        def exact(size):
            data = b""
            while len(data) < size:
                chunk = self.sock.recv(size - len(data))
                if not chunk:
                    raise ConnectionError
                data += chunk
            return data

        try:
            while True:
                first, second = exact(2)
                length = second & 0x7F
                if length == 126:
                    length = struct.unpack("!H", exact(2))[0]
                elif length == 127:
                    length = struct.unpack("!Q", exact(8))[0]
                payload = exact(length)
                opcode = first & 0x0F
                if opcode == 9:  # ttyd closes the connection without a pong.
                    self.frame(10, payload)
                # The output of the terminal starts with "0".
                elif opcode in (1, 2) and payload[:1] == b"0":
                    self.answer(payload[1:])
                    with self.changed:
                        self.output += payload[1:]
                        self.changed.notify_all()
        except (ConnectionError, OSError):
            pass

    # fish waits for the answers of the terminal to these queries. The answers
    # are those of xterm.js, the terminal of the app.
    ANSWERS = {
        b"\x1b[6n": b"\x1b[1;1R",  # cursor position
        b"\x1b[c": b"\x1b[?1;2c",  # primary device attributes
        b"\x1b[0c": b"\x1b[?1;2c",
    }

    def answer(self, output):
        for query, reply in self.ANSWERS.items():
            for _ in range(output.count(query)):
                self.frame(2, b"0" + reply)

    def wait_for(self, text, timeout=60):
        deadline = time.monotonic() + timeout
        with self.changed:
            while text.encode() not in self.output:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    tail = self.output[-600:].decode(errors="replace")
                    raise TimeoutError(f"no {text!r} in the terminal: {tail!r}")
                self.changed.wait(remaining)

    def run(self, command):
        self.frame(2, b"0" + command.encode() + b"\r")

    def value(self, name, expression, timeout=60):
        """The output of the fish EXPRESSION. The typed command does not
        contain the result line, so the echo of the input does not match."""
        self.run(f"printf '<{name}:%s>\\n' {expression}")
        pattern = re.compile(rb"<" + name.encode() + rb":([^<>%\r\n]*)>")
        with self.changed:
            start = len(self.output)
            deadline = time.monotonic() + timeout
            while True:
                values = pattern.findall(self.output[start:])
                if values:
                    return values[-1].decode(errors="replace")
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise TimeoutError(f"no value for {name}")
                self.changed.wait(remaining)


failures = 0


def check(name, function):
    global failures
    try:
        detail = function()
        print(f"APP {name} ok" + (f" ({detail})" if detail else ""), flush=True)
        return True
    except Exception as error:  # noqa: BLE001 - each check reports its error.
        failures += 1
        print(f"APP {name} FAIL: {error!r}", flush=True)
        return False


def main():
    vm_service = VirtualMachineService()
    state = {}

    def guest_agent():
        state["session"], state["agent"] = vm_service.guest_agent.get(timeout=60)
        return f"{time.monotonic() - START:.1f} s after the start"

    def terminal():
        state["terminal"] = Terminal()
        # The app shows an error when the terminal is not ready in 30 s.
        elapsed = time.monotonic() - START
        if elapsed > 30:
            raise TimeoutError(f"ttyd after {elapsed:.1f} s")
        user = state["terminal"].value("user", "(id -un)")
        if user != "aldur":
            raise ValueError(user)
        return f"{elapsed:.1f} s after the start"

    def debian_service():
        state["debian"] = DebianService()
        state["debian"].set_port_listener()

    def clipboard_to_guest():
        text = "from Android " + base64.b16encode(os.urandom(4)).decode()
        state["debian"].update_clipboard(text)
        deadline = time.monotonic() + 10
        while True:
            pasted = state["terminal"].value("paste", "(wl-paste --no-newline)")
            if pasted == text:
                return None
            if time.monotonic() > deadline:
                raise ValueError(f"{pasted!r} != {text!r}")
            time.sleep(0.5)

    def clipboard_to_android():
        state["terminal"].run("printf 'from the guest' | wl-copy")
        deadline = time.monotonic() + 10
        while (text := state["debian"].read_clipboard()) != "from the guest":
            if time.monotonic() > deadline:
                raise ValueError(repr(text))
            time.sleep(0.5)

    def service_port_reported():
        # pcscd (smartcard.nix) listens before the app connects.
        deadline = time.monotonic() + 30
        while True:
            ports = state["debian"].ports.get(timeout=max(0.1, deadline - time.monotonic()))
            if 25963 in ports:
                return f"comm {ports[25963]!r}"

    def port_reported():
        state["terminal"].run("python3 -m http.server 8123 --bind 127.0.0.1 &")
        deadline = time.monotonic() + 30
        while True:
            ports = state["debian"].ports.get(timeout=max(0.1, deadline - time.monotonic()))
            if 8123 in ports:
                return f"comm {ports[8123]!r}"

    def reports_apart():
        # See the pace of the reports in ../agent.nix.
        times = state["debian"].report_times
        gap = min(b - a for a, b in zip(times, times[1:]))
        if gap < 0.5:
            raise ValueError(f"{gap:.3f} s between two of {len(times)} reports")
        return f"{gap:.1f} s or more between {len(times)} reports"

    def port_forwarding():
        listener = vsock_listen(5123)
        listener.settimeout(30)
        state["debian"].request_forwarding(8123, 5123)
        sock, _ = listener.accept()
        sock.settimeout(30)
        sock.sendall(b"GET / HTTP/1.0\r\n\r\n")
        response = b""
        while chunk := sock.recv(4096):
            response += chunk
        if not response.startswith(b"HTTP/1.0 200"):
            raise ValueError(response[:80])

    def storage_balloon():
        before = int(state["terminal"].value("before", "(cat /sys/fs/ext4/vda1/reserved_clusters)"))
        state["debian"].request_storage_balloon(1 << 30)
        deadline = time.monotonic() + 10
        while True:
            after = int(
                state["terminal"].value("after", "(cat /sys/fs/ext4/vda1/reserved_clusters)")
            )
            if after > before:
                return f"{before} -> {after} clusters"
            if time.monotonic() > deadline:
                raise ValueError(f"{before} -> {after} clusters")
            time.sleep(0.5)

    def shutdown():
        vm_service.shutdown_guest(state["session"], state["agent"])

    if check("guest-agent", guest_agent):
        check("terminal", terminal)
        if check("debian-service", debian_service) and "terminal" in state:
            check("clipboard-to-guest", clipboard_to_guest)
            check("clipboard-to-android", clipboard_to_android)
            check("service-port-reported", service_port_reported)
            if check("port-reported", port_reported):
                check("reports-apart", reports_apart)
                check("port-forwarding", port_forwarding)
            check("storage-balloon", storage_balloon)
        check("shutdown", shutdown)
    print(f"APP done failures={failures}", flush=True)


main()
