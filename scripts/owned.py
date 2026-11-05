"""Linux qualified-tool launcher. A failure is terminal for the outer PID namespace.
No destructor signals, descendant discovery, asynchronous reaping, or PID probes.
"""
import ctypes
import json
import os
import platform
import secrets
import selectors
import signal
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path


class OwnershipFailure(RuntimeError):
    pass


@dataclass(frozen=True)
class Completed:
    code: int
    stdout: bytes
    stderr: bytes


def check_policy(metadata):
    data = json.loads(Path(metadata).read_text(encoding="utf-8"))
    expected = {"size": 152, "handler_offset": 0, "handler_size": 8,
                "flags_offset": 136, "flags_size": 4, "sa_nocldwait": 2}
    if (platform.system() != "Linux" or platform.machine() != "x86_64"
            or platform.libc_ver()[0] != "glibc"
            or data.get("system") != "Linux" or data.get("machine") != "x86_64"
            or data.get("libc") != "glibc" or data.get("sigaction") != expected
            or ctypes.sizeof(ctypes.c_void_p) != 8 or sys.byteorder != "little"):
        raise OwnershipFailure("unqualified sigaction ABI")
    libc = ctypes.CDLL(None, use_errno=True)
    query = libc.sigaction
    query.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_void_p]
    query.restype = ctypes.c_int
    storage = ctypes.create_string_buffer(expected["size"])
    if query(signal.SIGCHLD, None, ctypes.byref(storage)) != 0:
        raise OwnershipFailure("SIGCHLD policy query failed")
    raw = storage.raw
    handler = int.from_bytes(raw[0:8], "little")
    flags = int.from_bytes(raw[136:140], "little")
    if handler != 0 or flags & 2:
        raise OwnershipFailure("SIGCHLD must be default without SA_NOCLDWAIT")


def run(argv, *, metadata, cwd=None, env=None, input_data=b"", timeout=180,
        observe=None, send=None):
    # The query is read-only and precedes fixtures, pipes and fork.
    check_policy(metadata)
    if not argv or len(input_data) > 131072 or not 0 < timeout <= 600:
        raise OwnershipFailure("launcher input bounds")
    observe = observe or (lambda pid, label: os.waitid(
        os.P_PID, pid, os.WEXITED | os.WNOHANG | os.WNOWAIT))
    send = send or (lambda target, sig: os.kill(target, sig))
    authority = True
    admitted = False
    observed = None
    pid = None
    selector = selectors.DefaultSelector()
    opened = set()
    captured = {"stdout": bytearray(), "stderr": bytearray(), "ack": bytearray()}
    eof = set()
    nonce = secrets.token_hex(16).encode("ascii")
    expected = b"READY:" + nonce + b"\n"
    scratch = tempfile.TemporaryFile()
    scratch.write(input_data)
    scratch.seek(0)

    def pipe():
        a, b = os.pipe()
        opened.update((a, b))
        return a, b

    def close(fd):
        if fd in opened:
            os.close(fd)
            opened.remove(fd)

    ack_r, ack_w = pipe()
    go_r, go_w = pipe()
    out_r, out_w = pipe()
    err_r, err_w = pipe()
    started = time.monotonic()
    try:
        pid = os.fork()
        if pid == 0:
            try:
                selector.close()
                os.setsid()
                for fd in (ack_r, go_w, out_r, err_r):
                    os.close(fd)
                os.dup2(scratch.fileno(), 0)
                os.dup2(out_w, 1)
                os.dup2(err_w, 2)
                os.close(out_w)
                os.close(err_w)
                if os.write(ack_w, expected) != len(expected):
                    os._exit(126)
                os.close(ack_w)
                if os.read(go_r, 2) != b"G":
                    os._exit(126)
                os.close(go_r)
                if cwd is not None:
                    os.chdir(cwd)
                os.execvpe(argv[0], list(argv), os.environ.copy() if env is None else env)
            except BaseException:
                os._exit(126)
        for fd in (ack_w, go_r, out_w, err_w):
            close(fd)
        for fd, name in ((ack_r, "ack"), (out_r, "stdout"), (err_r, "stderr")):
            os.set_blocking(fd, False)
            selector.register(fd, selectors.EVENT_READ, name)

        def inspect(label):
            nonlocal authority, observed
            try:
                info = observe(pid, label)
                if info is not None:
                    if info.si_pid != pid:
                        raise OwnershipFailure("unexpected wait identity")
                    observed = info
            except BaseException as exc:
                authority = False
                raise OwnershipFailure("wait authority lost; no more signals") from exc

        def signal_owned(sig):
            nonlocal authority
            if not authority:
                raise OwnershipFailure("signals disarmed")
            try:
                send(-pid if admitted else pid, sig)
            except BaseException as exc:
                authority = False
                raise OwnershipFailure("signal failed; signals permanently disarmed") from exc

        def pump(delay):
            for key, _ in selector.select(delay):
                fd, name = key.fd, key.data
                chunk = os.read(fd, 8192)
                if not chunk:
                    selector.unregister(fd)
                    close(fd)
                    eof.add(name)
                else:
                    maximum = 128 if name == "ack" else 65536
                    if len(captured[name]) + len(chunk) > maximum:
                        raise OwnershipFailure("bounded capture exceeded")
                    captured[name].extend(chunk)

        try:
            while True:
                now = time.monotonic()
                if now - started >= timeout:
                    raise OwnershipFailure("liveness deadline exceeded")
                if not admitted and now - started >= min(5, timeout):
                    raise OwnershipFailure("acknowledgement deadline exceeded")
                pump(0.02)
                if not admitted and "ack" in eof:
                    if bytes(captured["ack"]) != expected:
                        raise OwnershipFailure("invalid private acknowledgement")
                    # The selector/read may have crossed the admission deadline.
                    # Recheck after the real ACK/EOF, immediately before granting GO.
                    if time.monotonic() - started >= min(5, timeout):
                        raise OwnershipFailure("acknowledgement deadline exceeded before GO")
                    # The fresh session was acknowledged before granting execution.
                    admitted = True
                    if os.write(go_w, b"G") != 1:
                        raise OwnershipFailure("GO write failed")
                    close(go_w)
                inspect("observe-admitted" if admitted else "observe-handshake")
                if observed is not None and {"ack", "stdout", "stderr"} <= eof:
                    break
            if not admitted:
                raise OwnershipFailure("tool was not admitted")
            try:
                reaped, status = os.waitpid(pid, 0)
                authority = False
                if reaped != pid:
                    raise OwnershipFailure("final reap identity mismatch")
            except BaseException as exc:
                authority = False
                raise OwnershipFailure("final reap failed; signals disarmed") from exc
            return Completed(os.waitstatus_to_exitcode(status), bytes(captured["stdout"]),
                             bytes(captured["stderr"]))
        except BaseException as original:
            # All numeric signals, including escalation, precede the only final reap.
            # Dune workers can have other PGIDs. This is NOT complete tree cleanup.
            if authority:
                try:
                    signal_owned(signal.SIGTERM)
                    until = time.monotonic() + 0.2
                    while time.monotonic() < until:
                        inspect("cleanup-observe")
                        time.sleep(0.01)
                    signal_owned(signal.SIGKILL)
                    until = time.monotonic() + 0.5
                    while observed is None and time.monotonic() < until:
                        inspect("cleanup-observe")
                        time.sleep(0.01)
                    if observed is not None and authority:
                        try:
                            actual, _ = os.waitpid(pid, 0)
                            authority = False
                            if actual != pid:
                                raise OwnershipFailure("cleanup reap identity")
                        except BaseException:
                            authority = False
                except BaseException:
                    authority = False
            raise OwnershipFailure(
                "terminal owned-tool failure; cleanup may be incomplete; dispose PID namespace: "
                + str(original)) from original
    finally:
        selector.close()
        for fd in list(opened):
            try:
                close(fd)
            except OSError:
                pass
        scratch.close()


def authority_fault(metadata):
    # This deliberately leaves an unreaped child when wait authority is lost.
    # It is only valid as the final operation of a disposable PID namespace.
    if os.getpid() != 1:
        raise OwnershipFailure("authority fault requires disposable container PID 1")
    kills = []

    def observe(pid, label):
        if label == "observe-admitted":
            raise OSError("injected waitid authority fault")
        return os.waitid(os.P_PID, pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)

    def send(target, sig):
        kills.append((target, sig))
        os.kill(target, sig)

    try:
        run([sys.executable, "-c", "import time; time.sleep(30)"],
            metadata=metadata, observe=observe, send=send, timeout=5)
    except OwnershipFailure as exc:
        if kills or "wait authority lost" not in str(exc):
            raise OwnershipFailure("authority regression") from exc
        print("authority fault: zero OS signals after lost authority", flush=True)
        os._exit(79)
    raise OwnershipFailure("fault was not injected")
