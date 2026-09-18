#!/usr/bin/env python3
"""Compile the real shortcut codec, without starting the app or touching user defaults."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="clonie-shortcut-test-") as directory:
    temp = Path(directory)
    (temp / "main.swift").write_text(r'''
import AppKit

enum GlobalHotKey { enum Slot { case toggle } }
let suiteName = "clonie-shortcut-test-" + UUID().uuidString
let defaults = UserDefaults(suiteName: suiteName)!
defer { defaults.removePersistentDomain(forName: suiteName) }
let fallback = RecordingShortcut.defaultToggle
assert(RecordingShortcut.load(prefix: "test", fallback: fallback, defaults: defaults).key == "m")
let specialKey = "\"\\\n한글"
let original = RecordingShortcut(modifiers: [.command, .shift], key: specialKey)
RecordingShortcut.save(original, prefix: "test", defaults: defaults)
let loaded = RecordingShortcut.load(prefix: "test", fallback: fallback, defaults: defaults)
assert(loaded.key == specialKey && loaded.modifiers == original.modifiers)
let decoded = try JSONSerialization.jsonObject(with: Data(original.jsJSON.utf8)) as! [String: Any]
assert(decoded["key"] as? String == specialKey)
assert(decoded["cmd"] as? Bool == true && decoded["opt"] as? Bool == false)
assert(RecordingShortcut.fromJS(["shift": true, "key": "A"]) == nil)
assert(RecordingShortcut.fromJS(["key": "a"]) == nil)
assert(RecordingShortcut.fromJS(["ctrl": true, "shift": true, "key": "A"])?.key == "a")
defaults.set(-1, forKey: "testModifiers")
assert(RecordingShortcut.load(prefix: "test", fallback: fallback, defaults: defaults).key == "m")
print("shortcut codec: persistence, JSON roundtrip, typing guard, malformed defaults passed")
''')
    executable = temp / "shortcut-test"
    subprocess.run(["swiftc", str(ROOT / "Sources/Clonie/Config/RecordingShortcut.swift"),
                    str(temp / "main.swift"), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
