#!/usr/bin/env python3
"""Bundle the same local marketplace with the app; installation remains with the AI host."""
import argparse
import shutil
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("destination", type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
destination = args.destination
if destination.exists():
    parser.error("Destination already exists; leave the existing package intact")
destination.mkdir(parents=True)
for relative in (".agents/plugins/marketplace.json", ".claude-plugin/marketplace.json"):
    target = destination / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(root / relative, target)
shutil.copytree(root / "plugins/clonie", destination / "plugins/clonie",
                ignore=shutil.ignore_patterns(".DS_Store", "__pycache__", "*.pyc"))
shutil.copy2(root / "scripts/install-clonie-plugin.sh", destination / "install.sh")
shutil.copy2(root / "plugins/clonie/README.md", destination / "README.md")
print(f"Bundled Clonie plugin marketplace: {destination}")
