"""Run complete bot rounds, collect engine errors, and optionally capture results screenshots.

python tools/smoke_test.py --godot /path/to/godot --players 2
python tools/smoke_test.py --screenshots --players 4 --language en
The JSON/HTML summary is written to ignored audit-output/smoke/. Screenshots require a display.
"""
from __future__ import annotations

import argparse
import html
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

from test_game import ROOT, find_godot, run_engine, silence_native_crash_dialogs

GAMES = ("plane", "archery", "bowling", "skate", "ski", "basketball")


def main() -> int:
    silence_native_crash_dialogs()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot")
    parser.add_argument("--players", type=int, choices=(1, 2, 3, 4), default=2)
    parser.add_argument("--games", nargs="+", choices=GAMES, default=list(GAMES))
    parser.add_argument("--language", choices=("zh", "en"), default="zh")
    parser.add_argument("--screenshots", action="store_true")
    parser.add_argument("--timeout", type=float, default=240)
    parser.add_argument("--output", type=Path, default=ROOT / "audit-output" / "smoke")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    godot = find_godot(args.godot)
    rows = []
    for game in args.games:
        report = output / f"{game}.json"
        shot = output / f"{game}.png"
        report.unlink(missing_ok=True) # do not accept results left by a previous run
        shot.unlink(missing_ok=True)
        with tempfile.TemporaryDirectory(prefix="rs-smoke-") as temp:
            env = dict(os.environ, APPDATA=temp, XDG_DATA_HOME=temp, XDG_CONFIG_HOME=temp, XDG_CACHE_HOME=temp)
            # Configure the isolated save, not the real player's settings.
            user = Path(temp) / ("Godot/app_userdata/Regina Sports" if os.name == "nt" else "godot/app_userdata/Regina Sports")
            user.mkdir(parents=True, exist_ok=True)
            (user / "settings.cfg").write_text(f'[general]\nlanguage={int(args.language == "en")}\n[display]\nquality=0\n', encoding="utf-8")
            command = [godot, "--path", str(ROOT / "game"), f"res://scenes/{game}/{game}_game.tscn"]
            command += ["--resolution", "1600x900"] if args.screenshots else ["--headless", "--fixed-fps", "60"]
            command += ["--", f"--demo={args.players}", f"--smoke-report={report}"]
            if args.screenshots:
                command.append(f"--smoke-shot={shot}")
            start = time.monotonic()
            timed_out = False
            try:
                result = run_engine(command, env=env, timeout=args.timeout)
                log = result.stdout + result.stderr
                code = result.returncode
            except subprocess.TimeoutExpired as exc:
                timed_out = True
                def decode(value):
                    return value.decode("utf-8", "replace") if isinstance(value, bytes) else (value or "")
                log = decode(exc.stdout) + decode(exc.stderr)
                code = -1
            (output / f"{game}.log").write_text(log, encoding="utf-8")
            errors = [line for line in log.splitlines() if line.startswith(("ERROR:", "SCRIPT ERROR:"))]
            # Sandboxed Windows can deny access to the system certificate store. Game rendering
            # and local UDP do not use TLS; expose this separately instead of hiding game errors.
            environment = [line for line in errors if "Failed to read the root certificate store" in line]
            errors = [line for line in errors if line not in environment]
            ok = code == 0 and report.exists() and f"RS_SMOKE_DONE: {game}" in log and not errors
            if args.screenshots:
                ok = ok and shot.exists()
            row = {"game": game, "passed": ok, "timeout": timed_out, "seconds": round(time.monotonic() - start, 2),
                   "errors": errors, "environment_warnings": environment, "screenshot": shot.name if shot.exists() else None}
            rows.append(row)
            print(f'{game}: {"PASS" if ok else "FAIL"} ({row["seconds"]}s)', flush=True)
    (output / "summary.json").write_text(json.dumps(rows, indent=2), encoding="utf-8")
    cards = []
    for row in rows:
        image = f'<img src="{row["screenshot"]}" alt="{row["game"]} results">' if row["screenshot"] else ""
        cards.append(f'<article><h2>{row["game"]}: {"PASS" if row["passed"] else "FAIL"}</h2>{image}<pre>{html.escape(chr(10).join(row["errors"]))}</pre></article>')
    (output / "index.html").write_text('<!doctype html><meta charset="utf-8"><title>Regina Sports smoke tests</title><style>body{background:#101521;color:#eee;font:16px system-ui;padding:24px}main{display:grid;grid-template-columns:1fr 1fr;gap:20px}img{width:100%}pre{white-space:pre-wrap}</style><h1>Regina Sports smoke tests</h1><main>' + "".join(cards) + '</main>', encoding="utf-8")
    return 0 if all(row["passed"] for row in rows) else 1


if __name__ == "__main__":
    raise SystemExit(main())
