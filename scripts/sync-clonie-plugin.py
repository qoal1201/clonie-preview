#!/usr/bin/env python3
"""Keep the distributable plugin's instructions and license equal to their sources."""
import argparse
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--check", action="store_true", help="Report stale copies without writing")
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
copies = [(root / "LICENSE", root / "plugins/clonie/LICENSE")]
for name in ("clonie", "clonie-session-record", "clonie-init"):
    source_dir = root / ".agents/skills" / name
    for source in sorted(source_dir.rglob("*")):
        if source.is_file() and source.suffix in (".md", ".yaml", ".sh"):
            copies.append((source, root / "plugins/clonie/skills" / name / source.relative_to(source_dir)))

stale = []
for source, target in copies:
    if target.exists() and target.read_bytes() == source.read_bytes():
        continue
    if args.check:
        stale.append(str(target.relative_to(root)))
    else:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(source.read_bytes())
        print(f"Synced {target.relative_to(root)}")
if stale:
    parser.exit(1, "Run python3 scripts/sync-clonie-plugin.py:\n" + "\n".join(stale) + "\n")
