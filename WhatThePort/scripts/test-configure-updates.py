import base64
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("configure_updates", Path(__file__).with_name("configure-updates.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ReleaseConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.env = {
            "REQUIRE_UPDATES": "--release",
            "SPARKLE_FEED_URL": "https://example.com/updates/appcast.xml",
            "SPARKLE_PUBLIC_KEY": base64.b64encode(bytes(range(32))).decode(),
            "WTP_VERSION": "2.2",
            "WTP_BUILD": "4",
        }

    def test_release_embeds_configuration_and_versions(self):
        info = module.configure({}, self.env)
        self.assertEqual(info["SUFeedURL"], self.env["SPARKLE_FEED_URL"])
        self.assertEqual(info["SUPublicEDKey"], self.env["SPARKLE_PUBLIC_KEY"])
        self.assertEqual(info["CFBundleShortVersionString"], "2.2")
        self.assertEqual(info["CFBundleVersion"], "4")

    def test_unconfigured_local_build_preserves_metadata(self):
        self.assertEqual(module.configure({"CFBundleVersion": "3"}, {}), {"CFBundleVersion": "3"})

    def test_host_app_version_does_not_override_bundle_version(self):
        info = {"CFBundleShortVersionString": "2.1", "CFBundleVersion": "3"}
        self.assertEqual(module.configure(dict(info), {"APP_VERSION": "0.87.3", "APP_BUILD": "999"}), info)

    def test_release_requires_configuration(self):
        with self.assertRaises(ValueError):
            module.configure({}, {"REQUIRE_UPDATES": "--release"})

    def test_rejects_insecure_or_invalid_feeds(self):
        for feed in ["http://example.com/appcast.xml", "https:///appcast.xml", "https://user:pass@example.com/appcast.xml", "https://example.com/appcast.xml?token=secret", "https://example.com/appcast.xml#feed", "https://example.com/update.zip"]:
            with self.subTest(feed=feed), self.assertRaises(ValueError):
                module.configure({}, dict(self.env, SPARKLE_FEED_URL=feed))

    def test_rejects_missing_or_malformed_keys_even_for_local_builds(self):
        for key in ["", "not a key", base64.b64encode(b"short").decode()]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                module.configure({}, dict(self.env, SPARKLE_PUBLIC_KEY=key, REQUIRE_UPDATES=""))

    def test_rejects_invalid_versions(self):
        for value in ["../4", "v2.2", "4-beta", "4/5"]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                module.configure({}, dict(self.env, WTP_BUILD=value))


if __name__ == "__main__":
    unittest.main()
