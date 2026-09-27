"""Validate public build-time service metadata; reject secrets and unsafe endpoints."""
import json
import sys
from urllib.parse import urlsplit


def require(condition):
    if not condition:
        raise ValueError("invalid public metadata")


def validate(value):
    require(set(value) == {"relay", "issuer", "desktopClientID", "chatClientID"})
    for key in ("relay", "issuer"):
        url = urlsplit(value[key])
        require(url.scheme == "https" and url.hostname)
        require(not url.username and not url.password and not url.query and not url.fragment)
        require(url.path in ("", "/"))
    for key in ("desktopClientID", "chatClientID"):
        value_id = value[key]
        require(isinstance(value_id, str) and 0 < len(value_id.encode()) <= 512)
        require(not any(c.isspace() for c in value_id))
    require(value["desktopClientID"] != value["chatClientID"])


if __name__ == "__main__":
    try:
        with open(sys.argv[1], "rb") as source:
            data = source.read(16_385)
        require(len(data) <= 16_384)
        validate(json.loads(data))
    except Exception:
        sys.exit("Invalid remote service metadata; build stopped (values redacted).")
