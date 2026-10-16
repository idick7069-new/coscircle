"""Safely replace the ZenRows credential from an interactive GCP terminal."""

import getpass
import grp
import json
import os
import re
import socket
import tempfile
from pathlib import Path
from zenrows_config import CONFIG_PATH


def main():
    if not re.fullmatch(r"coscircle-free-vm(?:\..+)?", socket.gethostname()) or os.geteuid() != 0:
        raise SystemExit("Run with sudo on coscircle-free-vm only.")
    if not os.isatty(0):
        raise SystemExit("An interactive terminal is required. Do not pass a key as an argument.")
    key = getpass.getpass("ZenRows API key (hidden): ").strip()
    if not key or key != getpass.getpass("Confirm API key (hidden): ").strip():
        raise SystemExit("Keys missing or do not match; nothing changed.")
    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".zenrows-", dir=CONFIG_PATH.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as output:
            os.fchmod(output.fileno(), 0o640)
            os.fchown(output.fileno(), 0, grp.getgrnam("coscircle").gr_gid)
            json.dump({"enabled": True, "apiKey": key}, output)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, CONFIG_PATH)
    finally:
        Path(temporary).unlink(missing_ok=True)
    print("Saved root:coscircle 0640. No key printed. No restart required.")


if __name__ == "__main__":
    main()
