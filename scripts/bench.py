#!/usr/bin/env python3
"""Run one benchmark with host-pressure, RSS, output and time limits."""

import argparse
import contextlib
import fcntl
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time


def host_pressure():
    if sys.platform == "darwin":
        level = int(subprocess.check_output(
            ["sysctl", "-n", "kern.memorystatus_vm_pressure_level"], text=True))
        return None if level == 1 else f"macOS memory pressure level {level}"
    if sys.platform.startswith("linux"):
        values = {}
        for line in Path("/proc/meminfo").read_text().splitlines():
            key, value = line.split(":", 1)
            values[key] = int(value.split()[0])
        if values["MemAvailable"] < max(512 * 1024, values["MemTotal"] // 10):
            return "Linux available memory below reserve"
        return None
    raise RuntimeError("Memory pressure monitoring requires macOS or Linux")


def group_rss(pid):
    output = subprocess.check_output(["ps", "-axo", "pgid=,rss="], text=True)
    return sum(int(rss) * 1024 for group, rss in
               (line.split() for line in output.splitlines()) if int(group) == pid)


def stop_group(process):
    # The child owns a new session; signals reach its descendants in that group.
    with contextlib.suppress(ProcessLookupError):
        os.killpg(process.pid, signal.SIGTERM)
    try:
        process.wait(timeout=0.5)
    except subprocess.TimeoutExpired:
        pass
    with contextlib.suppress(ProcessLookupError):
        os.killpg(process.pid, signal.SIGKILL)
    process.wait()


@contextlib.contextmanager
def benchmark_lock():
    path = Path(tempfile.gettempdir()) / f"hxnme-benchmark-{os.getuid()}.lock"
    with path.open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError("Another guarded benchmark is running") from None
        yield


def run(command, memory_mib=512, timeout=60, output_mib=8):
    with benchmark_lock():
        pressure = host_pressure()
        if pressure:
            raise RuntimeError(f"Benchmark not started: {pressure}")
        fd, name = tempfile.mkstemp(prefix="hxnme-benchmark-", suffix=".log")
        print(f"Benchmark log: {name}", file=sys.stderr, flush=True)
        peak = 0
        reason = None
        with os.fdopen(fd, "wb") as output:
            process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT,
                                       start_new_session=True)
            start = time.monotonic()
            try:
                while True:
                    peak = max(peak, group_rss(process.pid))
                    pressure = host_pressure()
                    if pressure:
                        reason = pressure
                    elif peak > memory_mib * 1048576:
                        reason = f"Process group exceeded {memory_mib:g} MiB RSS"
                    elif os.fstat(output.fileno()).st_size > output_mib * 1048576:
                        reason = f"Output exceeded {output_mib:g} MiB"
                    elif time.monotonic() - start > timeout:
                        reason = f"Time exceeded {timeout:g} seconds"
                    if reason or process.poll() is not None:
                        break
                    time.sleep(0.1)
            finally:
                stop_group(process)
        print(f"Peak sampled group RSS: {peak / 1048576:.1f} MiB", file=sys.stderr)
        if reason:
            raise RuntimeError(f"Benchmark stopped: {reason}; log: {name}")
        if process.returncode:
            raise RuntimeError(f"Benchmark exited {process.returncode}; log: {name}")
        # Keep logs on disk; printing is bounded even when the child is noisy.
        with open(name, "rb") as log:
            sys.stdout.buffer.write(log.read(8192))
        return name


def positive(value):
    value = float(value)
    if not 0 < value < float("inf"):
        raise argparse.ArgumentTypeError("Expected a finite positive number")
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__, epilog="Example: scripts/bench.py -- ash --preset game bench.hl")
    parser.add_argument("--memory-mib", type=positive, default=512)
    parser.add_argument("--timeout", type=positive, default=60)
    parser.add_argument("--output-mib", type=positive, default=8)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command
    if command[:1] == ["--"]:
        command = command[1:]
    if not command:
        parser.error("Supply a benchmark command after --")
    try:
        run(command, args.memory_mib, args.timeout, args.output_mib)
    except (RuntimeError, OSError, ValueError, subprocess.SubprocessError) as error:
        print(error, file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("Benchmark interrupted", file=sys.stderr)
        return 130
    return 0


if __name__ == "__main__":
    sys.exit(main())
