"""실제 인증서 없이 잘못된 스토어 프로파일을 거절하는 경계를 검증한다."""
import datetime
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / "scripts"))
from store_profile import entitlements_for_store


class StoreProfileTests(unittest.TestCase):
    def setUp(self):
        self.now = datetime.datetime(2026, 10, 26, tzinfo=datetime.timezone.utc)
        self.identifier = "kr.co.zcre.bunny.prototype"
        self.profile = {
            "ExpirationDate": datetime.datetime(2027, 1, 1),
            "TeamIdentifier": ["TESTTEAM"], "ApplicationIdentifierPrefix": ["TESTPREFIX"],
            "Entitlements": {"com.apple.application-identifier": "TESTPREFIX." + self.identifier,
                             "com.apple.developer.team-identifier": "TESTTEAM"}}

    def validate(self):
        return entitlements_for_store(self.profile, self.identifier,
                                      {"com.apple.security.app-sandbox": True}, self.now)

    def test_valid_profile_keeps_minimum_requested_permissions(self):
        result = self.validate()
        self.assertTrue(result["com.apple.security.app-sandbox"])
        self.assertEqual(len(result), 3)

    def test_expired_profile_is_rejected(self):
        self.profile["ExpirationDate"] = datetime.datetime(2026, 1, 1)
        with self.assertRaises(ValueError): self.validate()

    def test_other_app_or_wildcard_is_rejected(self):
        for appid in ["TESTPREFIX.other.app", "TESTPREFIX.*"]:
            self.profile["Entitlements"]["com.apple.application-identifier"] = appid
            with self.assertRaises(ValueError): self.validate()

    def test_development_profile_is_rejected(self):
        self.profile["ProvisionedDevices"] = ["TEST-DEVICE"]
        with self.assertRaises(ValueError): self.validate()

    def test_team_mismatch_is_rejected(self):
        self.profile["Entitlements"]["com.apple.developer.team-identifier"] = "OTHERTEAM"
        with self.assertRaises(ValueError): self.validate()


if __name__ == "__main__": unittest.main()
