"""Load the production-only ZenRows key without exposing it to process arguments."""

import json
import re
from pathlib import Path

CONFIG_PATH = Path("/etc/coscircle/zenrows.json")


def load_config(hostname, path=CONFIG_PATH):
    if hostname != "www.doujin.com.tw":
        return None
    try:
        mode = path.stat().st_mode
        if mode & 0o007 or mode & 0o022:
            raise ValueError("curl_zenrows_config_permissions")
        config = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return None
    except (OSError, json.JSONDecodeError):
        raise ValueError("curl_zenrows_config_unreadable") from None
    if not isinstance(config, dict) or not isinstance(config.get("enabled"), bool):
        raise ValueError("curl_zenrows_config_invalid")
    if not config["enabled"]:
        return None
    key = config.get("apiKey")
    if not isinstance(key, str) or not key.strip():
        raise ValueError("curl_zenrows_key_missing")
    return {"apiKey": key.strip()}


def fetch_html(url, config, session_factory):
    # No DataImpulse hop, impersonation, browser process, or client-side retries.
    with session_factory(trust_env=False) as session:
        try:
            response = session.get(
                "https://api.zenrows.com/v1/",
                params={"apikey": config["apiKey"], "url": url,
                        "js_render": "true", "premium_proxy": "true",
                        "original_status": "true"},
                proxy="", timeout=180, allow_redirects=False, verify=True,
            )
        except Exception:
            return {"error": "curl_zenrows_request_failed"}
        if len(response.content) > 20 * 1024 * 1024:
            return {"error": "curl_zenrows_response_too_large"}
        headers = {key.lower(): value for key, value in response.headers.items()}
        # Provider URLs and arbitrary error bodies may contain credentials.
        safe_headers = {key: headers[key] for key in
                        ("content-type", "cf-mitigated", "x-request-id", "x-request-cost",
                         "x-key-credits-remaining") if key in headers}
        if not 200 <= response.status_code < 300:
            return {"error": "curl_zenrows_http_error", "providerStatus": response.status_code,
                    "headers": safe_headers}
        data = response.text.replace(config["apiKey"], "[REDACTED]")
        # ZenRows can label returned raw HTML as text/plain. Do not accept JSON/errors.
        if (str(safe_headers.get("content-type", "")).lower().startswith("text/plain")
                and re.search(r"<!doctype\s+html\b|<html(?:\s|>)", data[:4096], re.I)):
            safe_headers["content-type"] = "text/html; charset=utf-8"
        return {"status": response.status_code, "headers": safe_headers, "data": data}
