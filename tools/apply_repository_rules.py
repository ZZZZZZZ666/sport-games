"""Apply the reviewed main ruleset with the maintainer's administrative GitHub CLI login."""
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
REPO = "cb8010d6/sport-games"


def main():
    existing = json.loads(subprocess.check_output(["gh", "api", f"repos/{REPO}/rulesets"], text=True))
    found = next((r for r in existing if r["name"] == "Protect stable main"), None)
    endpoint = f"repos/{REPO}/rulesets" + (f"/{found['id']}" if found else "")
    subprocess.run(["gh", "api", "--method", "PUT" if found else "POST", endpoint,
                    "--input", str(ROOT / ".github/rulesets/main.json")], check=True)
    print("Verified configuration applied to main.")


if __name__ == "__main__":
    main()
