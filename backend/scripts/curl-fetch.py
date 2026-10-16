"""Fetch approved public event sources on the production VM only."""

import json
import re
import socket
import sys
from urllib.parse import urlsplit
from zenrows_config import load_config, fetch_html

ALLOWED_HOSTS = {"www.doujin.com.tw", "cosmos.oen.tw", "acosta.jp"}


def fetch(url, session_factory=None):
    if not re.fullmatch(r"coscircle-free-vm(?:\..+)?", socket.gethostname()):
        return {"error": "gcp_only_source_fetch"}
    target = urlsplit(url)
    if (target.scheme != "https" or target.hostname not in ALLOWED_HOSTS
            or target.username or target.password or target.port not in (None, 443)):
        return {"error": "curl_source_url_not_allowed"}
    try:
        zenrows = load_config(target.hostname)
    except ValueError as error:
        return {"error": str(error)}
    if target.hostname == "www.doujin.com.tw" and not zenrows:
        return {"error": "curl_zenrows_config_required"}
    if session_factory is None:
        try:
            from curl_cffi.requests import Session
        except ImportError:
            return {"error": "curl_cffi_dependency_missing"}
        session_factory = Session
    if zenrows:
        return fetch_html(url, zenrows, session_factory)
    headers = {
        "Accept-Language": "zh-TW,zh;q=0.9,ja;q=0.8,en;q=0.6",
        "User-Agent": "CosCircleBot/1.0 (+https://coscircle.app)",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    }
    with session_factory(trust_env=False) as session:
        response = session.get(
            url,
            timeout=20,
            allow_redirects=False,
            proxy="",
            verify=True,
            headers=headers,
        )
        if len(response.content) > 20 * 1024 * 1024:
            return {"error": "curl_source_response_too_large"}
        return {
            "status": response.status_code,
            "headers": {key.lower(): value for key, value in response.headers.items()},
            "data": response.text,
        }


def main():
    try:
        result = fetch(sys.argv[1])
    except Exception:
        result = {"error": "curl_source_request_failed"}
    print(json.dumps(result, ensure_ascii=True))


if __name__ == "__main__":
    main()
