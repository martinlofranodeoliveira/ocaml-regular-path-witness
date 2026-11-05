"""A real ACK/EOF with a controlled clock crossing; never execute expired work.
This is a deterministic deadline-boundary regression, not a hard real-time test.
"""
from pathlib import Path
import json
import os
import selectors
import sys
import time
from unittest.mock import patch
import owned

ROOT = Path(__file__).resolve().parents[1]
real_selector = selectors.DefaultSelector
real_read, real_write, real_waitpid, real_kill = os.read, os.write, os.waitpid, os.kill
real_clock = time.monotonic
state = {"ack_fd": None, "ack": bytearray(), "ack_eof": False, "offset": 0.0,
         "clock_after_ack": 0, "go_attempts": 0, "reaps": 0, "order": []}


class ControlledSelector:
    def __init__(self):
        self.inner = real_selector()

    def register(self, fd, events, data=None):
        if data == "ack":
            state["ack_fd"] = fd
        return self.inner.register(fd, events, data)

    def unregister(self, fd):
        return self.inner.unregister(fd)

    def select(self, timeout=None):
        # Real kernel readiness, including the acknowledged child's private pipe.
        return self.inner.select(timeout)

    def close(self):
        self.inner.close()


def clock():
    if state["ack_eof"]:
        state["clock_after_ack"] += 1
    return real_clock() + state["offset"]


def read(fd, count):
    data = real_read(fd, count)
    if fd == state["ack_fd"]:
        if data:
            state["ack"].extend(data)
        else:
            assert bytes(state["ack"]).startswith(b"READY:")
            assert bytes(state["ack"]).endswith(b"\n")
            state["ack_eof"] = True
            # Advance only after the real acknowledgement has fully arrived.
            state["offset"] = 10.0
    return data


def write(fd, data):
    if data == b"G":
        state["go_attempts"] += 1
        # Even a regressed implementation may not execute expired helper work.
        raise AssertionError("expired admission attempted GO")
    return real_write(fd, data)


def kill(target, sig):
    assert state["reaps"] == 0, "signal after final reap"
    state["order"].append("signal")
    return real_kill(target, sig)


def waitpid(pid, options):
    result = real_waitpid(pid, options)
    assert result[0] == pid and pid > 0
    state["reaps"] += 1
    state["order"].append("reap")
    return result


def main():
    # This script has its own disposable parent and no other child/reaper.
    with patch.object(owned.selectors, "DefaultSelector", ControlledSelector), \
         patch.object(owned.time, "monotonic", clock), \
         patch.object(owned.os, "read", read), \
         patch.object(owned.os, "write", write), \
         patch.object(owned.os, "kill", kill), \
         patch.object(owned.os, "waitpid", waitpid):
        try:
            owned.run([sys.executable, "-c", "raise SystemExit('expired work executed')"],
                      metadata=ROOT / "dependency-metadata/platform.json", timeout=5)
        except owned.OwnershipFailure as error:
            assert "acknowledgement deadline exceeded before GO" in str(error), str(error)
        else:
            raise AssertionError("expired acknowledgement was admitted")
    assert state["ack_eof"] and state["clock_after_ack"] > 0
    assert state["go_attempts"] == 0
    assert state["reaps"] == 1 and state["order"][-1] == "reap"
    print(json.dumps({"real_ack_and_eof": True, "controlled_deadline_crossing": True,
                      "go_attempts": 0, "direct_child_reaped": True,
                      "signals_before_final_reap": True, "hard_realtime_claim": False}))


if __name__ == "__main__":
    main()
