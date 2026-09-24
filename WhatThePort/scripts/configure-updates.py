#!/usr/bin/env python3
"""Validate release inputs and write bundle metadata without editing the source plist."""
import base64
import os
from pathlib import Path
import plistlib
import re
import sys
from urllib.parse import urlsplit


def configure(info, env):
    feed = env.get("SPARKLE_FEED_URL", "")
    key = env.get("SPARKLE_PUBLIC_KEY", "")
    if feed or key or env.get("REQUIRE_UPDATES") == "--release":
        url = urlsplit(feed)
        if (url.scheme != "https" or not url.hostname or url.username or url.password
                or url.query or url.fragment or not url.path.endswith("/appcast.xml")):
            raise ValueError("SPARKLE_FEED_URL must be an HTTPS URL ending in /appcast.xml (no credentials, query or fragment)")
        try:
            valid_key = len(base64.b64decode(key, validate=True)) == 32
        except ValueError:
            valid_key = False
        if not valid_key:
            raise ValueError("SPARKLE_PUBLIC_KEY must be the Ed25519 public key from Sparkle's generate_keys tool")
        info["SUFeedURL"] = feed
        info["SUPublicEDKey"] = key
    for variable, plist_key in [("WTP_VERSION", "CFBundleShortVersionString"), ("WTP_BUILD", "CFBundleVersion")]:
        value = env.get(variable, "")
        if value:
            if not re.fullmatch(r"[0-9]+(?:\.[0-9]+)*", value):
                raise ValueError(f"{variable} must contain only numeric version components")
            info[plist_key] = value
    return info


def main():
    source, destination = map(Path, sys.argv[1:])
    try:
        info = configure(plistlib.loads(source.read_bytes()), os.environ)
    except ValueError as error:
        sys.exit(str(error))
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(plistlib.dumps(info, sort_keys=False))


if __name__ == "__main__":
    main()
