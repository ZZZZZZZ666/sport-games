"""Run game shell regression tests without touching the player's profiles or records.

Usage: python tools/test_game.py --godot /path/to/godot
Requires the standard Godot import step first: godot --headless --path game --editor --import --quit
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parent.parent


def silence_native_crash_dialogs() -> None:
    """Only this test process and its children inherit this mode; system settings stay intact.

    A native failure must return to the runner as a failure instead of opening the Windows
    JIT-debugger picker (which may itself fail on computers without Visual Studio).
    """
    if os.name == "nt":
        import ctypes
        ctypes.windll.kernel32.SetErrorMode(0x0002 | 0x8000) # SEM_NOGPFAULTERRORBOX | SEM_NOOPENFILEERRORBOX


def run_engine(command: list[str], env: dict[str, str], timeout: float) -> subprocess.CompletedProcess:
    """On timeout, stop the owned engine tree, including the Windows console wrapper's child."""
    silence_native_crash_dialogs()
    process = subprocess.Popen(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               text=True, encoding="utf-8", errors="replace", start_new_session=os.name != "nt")
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        if os.name == "nt":
            subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
        else:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        try:
            stdout, stderr = process.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            raise exc
        raise subprocess.TimeoutExpired(command, timeout, stdout, stderr) from exc
    return subprocess.CompletedProcess(command, process.returncode, stdout, stderr)


def find_godot(explicit: str | None) -> str:
    candidate = explicit or os.environ.get("REGINA_GODOT") or shutil.which("godot")
    if not candidate:
        local = list((ROOT / "tools" / "godot").glob("*console.exe"))
        if local:
            candidate = str(local[0])
    if not candidate:
        raise SystemExit("Godot not found; use --godot or REGINA_GODOT.")
    return str(Path(candidate).resolve()) if Path(candidate).exists() else candidate


def main() -> int:
    silence_native_crash_dialogs()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot")
    parser.add_argument("--party", action="store_true", help="also run the complete three-event party flow")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="rs-shell-tests-") as temp:
        env = dict(os.environ, RS_TEST_MODE="1", APPDATA=temp, XDG_DATA_HOME=temp,
                   XDG_CONFIG_HOME=temp, XDG_CACHE_HOME=temp)
        result = run_engine([find_godot(args.godot), "--headless", "--path", str(ROOT / "game"),
                                 "res://tests/test_shell.tscn", "--log-file", str(Path(temp) / "game.log")],
                                env=env, timeout=60)
        print(result.stdout)
        print(result.stderr)
        # Godot sometimes returns 0 after a script error; also require our explicit completion marker.
        output = result.stdout + result.stderr
        if result.returncode != 0 or "RS_SHELL_TESTS: 0 failures" not in output or "SCRIPT ERROR" in output:
            return 1
    if args.party:
        with tempfile.TemporaryDirectory(prefix="rs-party-tests-") as temp:
            env = dict(os.environ, RS_TEST_MODE="1", APPDATA=temp, XDG_DATA_HOME=temp,
                       XDG_CONFIG_HOME=temp, XDG_CACHE_HOME=temp)
            result = run_engine([find_godot(args.godot), "--headless", "--fixed-fps", "60", "--path", str(ROOT / "game"),
                                     "res://tests/test_party_flow.tscn", "--log-file", str(Path(temp) / "game.log"), "--", "--demo=2", "--round=5"],
                                    env=env, timeout=120)
            output = result.stdout + result.stderr
            print(output)
            return 0 if result.returncode == 0 and "RS_PARTY_FLOW: PASS" in output and "SCRIPT ERROR" not in output else 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
