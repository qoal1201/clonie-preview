#!/usr/bin/env python3
"""Check public documentation and tracked-file hygiene; not a security audit."""
import argparse
import re
import subprocess
from pathlib import Path
from urllib.parse import unquote, urlsplit


def check(root: Path) -> list[str]:
    paths = subprocess.check_output(
        ["git", "-C", str(root), "ls-files", "-z"], text=True
    ).split("\0")
    errors = []
    for name in filter(None, paths):
        path = Path(name)
        if (path.name.startswith(".env") and path.name != ".env.example") or path.suffix.lower() in {
            ".p12", ".p8", ".pem", ".key", ".mobileprovision"
        } or any(part in {".clonie", ".build", "__pycache__"} for part in path.parts):
            errors.append(f"{name}: private or generated file must not be tracked")

    # These pages serve people installing and using the published app.
    # Technical source comments and legally necessary provenance are separate.
    for name in ["README.md", "INSTALL.md", "PRIVACY.md", "SECURITY.md", "RELEASE-NOTES.md", "CONTRIBUTING.md", "CHANGELOG.md"]:
        path = root / name
        if not path.is_file():
            errors.append(f"{name}: required public document missing")
            continue
        body = path.read_text()
        for number, line in enumerate(body.splitlines(), 1):
            if re.search(r"/Users/|clonie-desktop|current-work\.md|modoo-2gi|정본|판정선|인수 조건|세션 인계", line):
                errors.append(f"{name}:{number}: internal wording or local path")
        prose = re.sub(r"```.*?```", "", body, flags=re.S)
        targets = re.findall(r"!?\[[^\]]*\]\(([^\s)]+)(?:\s+\"[^\"]*\")?\)", prose)
        targets += re.findall(r'<img\s[^>]*src="([^"]+)"', prose)
        for target in targets:
            parsed = urlsplit(target.strip("<>"))
            if parsed.scheme or parsed.netloc:
                continue
            destination = path.parent / unquote(parsed.path) if parsed.path else path
            if not destination.exists():
                errors.append(f"{name}: missing relative link {target}")
            elif parsed.fragment and destination.suffix == ".md":
                headings = re.findall(r"^#{1,6}\s+(.+)$", destination.read_text(), re.M)
                anchors = {re.sub(r"[^\w\- ]", "", h.lower()).replace(" ", "-") for h in headings}
                anchors.update(re.findall(r'<a\s+id="([^"]+)"', destination.read_text()))
                if unquote(parsed.fragment) not in anchors:
                    errors.append(f"{name}: missing heading {target}")
    return errors


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    args = parser.parse_args()
    errors = check(args.root.resolve())
    for error in errors:
        print(error)
    print(f"Public repository checks: {len(errors)} error(s)")
    raise SystemExit(bool(errors))
