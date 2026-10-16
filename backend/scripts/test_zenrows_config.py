import json
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
import unittest
from unittest.mock import MagicMock
from zenrows_config import load_config, fetch_html


class ZenRowsTests(unittest.TestCase):
    def test_restricted_config_and_source_scope(self):
        with TemporaryDirectory() as directory:
            path = Path(directory) / "config.json"
            self.assertIsNone(load_config("www.doujin.com.tw", path))
            path.write_text(json.dumps({"enabled": True, "apiKey": "test-secret"}))
            path.chmod(0o640)
            self.assertEqual(load_config("www.doujin.com.tw", path), {"apiKey": "test-secret"})
            self.assertIsNone(load_config("acosta.jp", path))
            path.chmod(0o644)
            with self.assertRaisesRegex(ValueError, "permissions"):
                load_config("www.doujin.com.tw", path)

    def test_invalid_config_fails_closed(self):
        with TemporaryDirectory() as directory:
            path = Path(directory) / "config.json"
            path.touch(mode=0o600)
            for config in ([], {"enabled": True}, {"enabled": "true"}):
                path.write_text(json.dumps(config))
                with self.assertRaises(ValueError):
                    load_config("www.doujin.com.tw", path)

    def test_gateway_errors_and_exceptions_never_expose_key(self):
        session = MagicMock()
        client = session.return_value.__enter__.return_value
        client.get.return_value = SimpleNamespace(status_code=403, content=b"test-secret",
            text="test-secret", headers={"Location": "https://example.com/?apikey=test-secret"})
        result = fetch_html("https://www.doujin.com.tw/events/alist/all", {"apiKey": "test-secret"}, session)
        self.assertEqual(result["providerStatus"], 403)
        self.assertNotIn("test-secret", str(result))
        self.assertEqual(client.get.call_count, 1)
        client.get.side_effect = RuntimeError("URL contains test-secret")
        result = fetch_html("https://www.doujin.com.tw/", {"apiKey": "test-secret"}, session)
        self.assertEqual(result, {"error": "curl_zenrows_request_failed"})

    def test_only_html_body_normalizes_plain_text_content_type(self):
        for body, expected in (("<!DOCTYPE html><html>events</html>", "text/html; charset=utf-8"),
                               ('{"error":"failed"}', "text/plain")):
            session = MagicMock()
            session.return_value.__enter__.return_value.get.return_value = SimpleNamespace(
                status_code=200, content=body.encode(), text=body, headers={"Content-Type": "text/plain"})
            result = fetch_html("https://www.doujin.com.tw/", {"apiKey": "test-secret"}, session)
            self.assertEqual(result["headers"]["content-type"], expected)


if __name__ == "__main__":
    unittest.main()
