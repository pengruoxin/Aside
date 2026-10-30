"""Test only processes created by this fixture; no model or network needed."""
import os
import pathlib
import signal
import subprocess
import sys
import tempfile
import time

launcher = str(pathlib.Path(sys.argv[1]).resolve())
fixture = "import os,pathlib,sys,time; pathlib.Path(sys.argv[1]).write_text(str(os.getpid())); time.sleep(60)"


def child_pid(stamp):
    for _ in range(100):
        if stamp.exists():
            return int(stamp.read_text())
        time.sleep(0.05)
    raise AssertionError("Fixture child did not start")


def assert_stopped(pid):
    for _ in range(80):
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return
        time.sleep(0.05)
    raise AssertionError("Runtime child survived its owner")


with tempfile.TemporaryDirectory(prefix="aside-runtime-test-") as directory:
    stamp = pathlib.Path(directory) / "normal.pid"
    supervisor = subprocess.Popen([launcher, sys.executable, "-c", fixture, str(stamp)])
    try:
        pid = child_pid(stamp)
        supervisor.terminate()
        supervisor.wait(timeout=5)
        assert_stopped(pid)
    finally:
        if supervisor.poll() is None:
            supervisor.kill()
            supervisor.wait()

    stamp = pathlib.Path(directory) / "owner-death.pid"
    owner = subprocess.Popen([sys.executable, "-c", "import subprocess,sys; subprocess.run(sys.argv[1:])",
                              launcher, sys.executable, "-c", fixture, str(stamp)])
    try:
        pid = child_pid(stamp)
        owner.kill()  # Input method crashed or was forcibly unloaded.
        owner.wait(timeout=5)
        assert_stopped(pid)
    finally:
        if owner.poll() is None:
            owner.kill()
            owner.wait()

print("Runtime cleanup passed: normal stop and unexpected owner death.")
