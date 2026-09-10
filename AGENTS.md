# Clonie: instructions for installation and repository work

This repository contains a macOS alpha app. If a user supplies this URL and asks
to try Clonie, help them install the release rather than starting a source build.
Read README.md and INSTALL.md first. A request to inspect the repository alone
does not authorize installation or reading the user's personal documents.

## Install when the user asks to use the app

1. Check `uname -s`, `uname -m`, and `sw_vers -productVersion`.
   The current binary requires Apple Silicon and macOS 26 or later.
2. Check whether Ghostbar.app is already installed or running. Do not stop it,
   overwrite it, or change its connected folder without the user's agreement.
3. If Homebrew is available, use the exact tap and cask commands in README.md.
   Otherwise read `scripts/install.sh`, then run it with Bash. It installs to
   `~/Applications/Ghostbar.app`, checks the release SHA-256 and app signature,
   and refuses to overwrite an existing app. `--app-dir` selects another folder.
4. Confirm that the installed bundle exists and `codesign --verify --deep --strict`
   succeeds. This verifies its signature, not Apple notarization or first-launch success.
5. Open the installed app if the user requested to start using it. Let the user
   handle macOS first-launch approval and microphone/screen recording permissions.
   Never disable Gatekeeper or strip quarantine as an automatic workaround.
6. Offer the included sample-vault or let the user choose their own Markdown folder.
   Editing changes actual files. Never upload their vault, API keys, or screenshots
   to a public issue without explicit approval.

No API key, AI subscription, Python, Xcode, or source build is required for the
bundled app's basic exploration, editing, and local search. Apple speech model
preparation is a separate first-use step. Do not silently enable external AI drafting.

## Repository changes

Follow CONTRIBUTING.md. Preserve other people's changes. Tests and builds are
evidence of those checks only; do not claim a successful fresh-Mac install or
human voice test unless it was performed. Keep upstream and dependency notices.
New app releases must update the pinned version, URL, and SHA-256 in both
`Casks/clonie.rb` and `scripts/install.sh`. Keep published assets immutable.
