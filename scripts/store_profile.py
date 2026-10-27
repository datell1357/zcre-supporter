#!/usr/bin/env python3
"""Apple이 서명한 CMS를 security cms로 해독한 뒤 스토어 프로파일의 용도를 확인한다."""
import datetime
import plistlib
import sys
from pathlib import Path


def entitlements_for_store(profile, identifier, requested, now=None):
    now = now or datetime.datetime.now(datetime.timezone.utc)
    expiry = profile.get("ExpirationDate")
    if not isinstance(expiry, datetime.datetime) or expiry.replace(tzinfo=datetime.timezone.utc) <= now:
        raise ValueError("프로파일이 만료됐거나 만료 시각이 없습니다.")
    allowed = profile.get("Entitlements", {})
    if profile.get("ProvisionedDevices") or profile.get("ProvisionsAllDevices") or allowed.get("com.apple.security.get-task-allow") or allowed.get("get-task-allow"):
        raise ValueError("개발/기기 한정 프로파일은 스토어 배포에 사용할 수 없습니다.")
    teams = profile.get("TeamIdentifier", [])
    appid = allowed.get("com.apple.application-identifier", "")
    prefixes = profile.get("ApplicationIdentifierPrefix", [])
    if len(teams) != 1 or not any(appid == prefix + "." + identifier for prefix in prefixes):
        raise ValueError("프로파일의 Team 또는 명시적 App ID가 앱과 일치하지 않습니다.")
    if allowed.get("com.apple.developer.team-identifier") != teams[0]:
        raise ValueError("프로파일의 Team 식별자가 일치하지 않습니다.")
    result = dict(requested)
    result["com.apple.application-identifier"] = appid
    result["com.apple.developer.team-identifier"] = teams[0]
    return result


if __name__ == "__main__":
    profile, info, template, output = map(Path, sys.argv[1:])
    try:
        value = entitlements_for_store(plistlib.loads(profile.read_bytes()),
                                       plistlib.loads(info.read_bytes())["CFBundleIdentifier"],
                                       plistlib.loads(template.read_bytes()))
        output.write_bytes(plistlib.dumps(value))
    except (ValueError, KeyError, OSError) as error:
        sys.exit(str(error))
