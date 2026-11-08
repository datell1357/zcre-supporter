#!/usr/bin/env python3
"""기능 분류: 공증 DMG의 EdDSA 서명과 Sparkle 업데이트 피드 생성. 개인 키는 Keychain에 둔다."""
import argparse
import base64
import plistlib
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SPARKLE = ROOT / '.build/artifacts/sparkle/Sparkle/bin'
ACCOUNT = 'zcre-supporter'
NS = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', NS)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('dmg', type=Path)
    parser.add_argument('--app', type=Path, default=ROOT / 'dist/ZCRE 서포터.app')
    args = parser.parse_args()
    dmg = args.dmg.resolve()
    with (args.app / 'Contents/Info.plist').open('rb') as file:
        info = plistlib.load(file)
    version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
    expected = f'ZCRE-Supporter-{version}-macOS-universal-notarized.dmg'
    if dmg.name != expected:
        raise SystemExit('버전과 DMG 파일명이 일치하지 않습니다.')
    # 공개 키 일치를 먼저 확인해 다른 앱의 Keychain 키로 잘못 서명하지 않는다.
    public = subprocess.check_output([str(SPARKLE / 'generate_keys'), '--account', ACCOUNT, '-p'], text=True).strip()
    if public != info['SUPublicEDKey'] or len(base64.b64decode(public, validate=True)) != 32:
        raise SystemExit('앱 공개 키와 Keychain 서명 키가 일치하지 않습니다.')
    subprocess.run(['xcrun', 'stapler', 'validate', str(dmg)], check=True)
    signature = subprocess.check_output([str(SPARKLE / 'sign_update'), '--account', ACCOUNT, '-p', str(dmg)], text=True).strip()
    subprocess.run([str(SPARKLE / 'sign_update'), '--account', ACCOUNT, '--verify', str(dmg), signature], check=True)
    rss = ET.Element('rss', version='2.0')
    channel = ET.SubElement(rss, 'channel')
    ET.SubElement(channel, 'title').text = 'ZCRE 서포터 업데이트'
    item = ET.SubElement(channel, 'item')
    ET.SubElement(item, 'title').text = f'ZCRE 서포터 {version}'
    ET.SubElement(item, f'{{{NS}}}version').text = build
    ET.SubElement(item, f'{{{NS}}}shortVersionString').text = version
    ET.SubElement(item, f'{{{NS}}}minimumSystemVersion').text = '14.0'
    ET.SubElement(item, 'description').text = '로그인 확인 후 연결 창 자동 닫기 · 서명 검증 후 직접 업데이트 · 작업 타자음 개선'
    ET.SubElement(item, 'enclosure', {
        'url': f'https://github.com/datell1357/zcre-supporter/releases/download/v{version}/{expected}',
        'length': str(dmg.stat().st_size), 'type': 'application/octet-stream',
        f'{{{NS}}}edSignature': signature,
    })
    ET.indent(rss)
    target = ROOT / 'updates/appcast.xml'
    target.parent.mkdir(exist_ok=True)
    ET.ElementTree(rss).write(target, encoding='utf-8', xml_declaration=True)
    print(f'서명 검증 완료: {target} (버전 {version}, 빌드 {build})')


if __name__ == '__main__':
    main()
