import importlib.util
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import MagicMock, patch

spec = importlib.util.spec_from_file_location("curl_fetch", Path(__file__).with_name("curl-fetch.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class FetchTests(unittest.TestCase):
    def setUp(self):
        config = patch.object(module, "load_config", return_value=None)
        self.addCleanup(config.stop)
        self.config = config.start()

    def test_local_guard_runs_before_config_dependency_or_network(self):
        with patch.object(module.socket, "gethostname", return_value="frank-macbook"):
            self.assertEqual(module.fetch("https://www.doujin.com.tw/events/alist/all"),
                             {"error": "gcp_only_source_fetch"})
        self.config.assert_not_called()

    def test_only_approved_https_hosts(self):
        with patch.object(module.socket, "gethostname", return_value="coscircle-free-vm"):
            for url in ["http://www.doujin.com.tw/", "https://localhost/",
                        "https://www.doujin.com.tw:8080/", "https://user@www.doujin.com.tw/",
                        "https://www.doujin.com.tw.evil.example/"]:
                self.assertEqual(module.fetch(url), {"error": "curl_source_url_not_allowed"})

    def test_missing_disabled_or_invalid_zenrows_never_falls_back(self):
        session = MagicMock()
        with patch.object(module.socket, "gethostname", return_value="coscircle-free-vm"):
            self.assertEqual(module.fetch("https://www.doujin.com.tw/events/alist/all", session),
                             {"error": "curl_zenrows_config_required"})
            self.config.side_effect = ValueError("curl_zenrows_config_unreadable")
            self.assertEqual(module.fetch("https://www.doujin.com.tw/events/alist/all", session),
                             {"error": "curl_zenrows_config_unreadable"})
        session.assert_not_called()

    def test_supplemental_sources_use_honest_direct_http(self):
        with patch.object(module.socket, "gethostname", return_value="coscircle-free-vm"):
            for url in ("https://cosmos.oen.tw/events/test", "https://acosta.jp/area/over-sea/taiwan/"):
                session = MagicMock()
                session.return_value.__enter__.return_value.get.return_value = SimpleNamespace(
                    status_code=200, content=b"ok", text="ok", headers={"Content-Type": "text/html"})
                result = module.fetch(url, session)
                request = session.return_value.__enter__.return_value.get.call_args.kwargs
                self.assertNotIn("impersonate", request)
                self.assertEqual(request["proxy"], "")
                self.assertFalse(request["allow_redirects"])
                self.assertTrue(request["verify"])
                self.assertIn("CosCircleBot", request["headers"]["User-Agent"])
                self.assertEqual(result["status"], 200)

    def test_doujin_only_uses_cloud_gateway(self):
        self.config.return_value = {"apiKey": "test-secret"}
        session = MagicMock()
        session.return_value.__enter__.return_value.get.return_value = SimpleNamespace(
            status_code=200, content=b"ok", text="ok", headers={"Content-Type": "text/html"})
        with patch.object(module.socket, "gethostname", return_value="coscircle-free-vm"):
            result = module.fetch("https://www.doujin.com.tw/events/alist/all", session)
        request = session.return_value.__enter__.return_value.get.call_args
        self.assertEqual(request.args, ("https://api.zenrows.com/v1/",))
        self.assertEqual(request.kwargs["params"]["apikey"], "test-secret")
        self.assertEqual(request.kwargs["params"]["js_render"], "true")
        self.assertEqual(request.kwargs["proxy"], "")
        self.assertNotIn("impersonate", request.kwargs)
        self.assertNotIn("test-secret", str(result))


if __name__ == "__main__":
    unittest.main()
