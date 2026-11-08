# macOS 설치 창

720×460 포인트의 다크 배경(제목 막대를 포함한 창 높이 492pt)·민트색 드래그 화살표·짧은 2단계 안내를 사용한다. 앱과 Applications만 표시하며 앱을 자동 실행하거나 시스템 보안 설정을 바꾸지 않는다.

- Retina 화면은 TIFF의 1×/2× 표현을 사용한다.
- Finder 아이콘은 96pt, 이름은 12pt다. 아이콘 좌표는 (204, 215)와 (516, 215)다.
- HFS+의 한글 파일명은 NFD로 저장되므로 `.DS_Store`의 좌표 키도 NFD로 정규화한다.
- 이름표 뒤에 작은 밝은 바탕을 두어 Finder의 기본 검정 글씨도 읽을 수 있게 한다.
- 배경의 서명·공증 안내가 사실과 일치하도록 포함 앱의 Developer ID 서명과 공증 티켓을 패키징 전에 검사한다.
- 디자인 변경만으로 앱 실행 파일이나 이미 배포한 앱 버전은 바뀌지 않는다. DMG 자체는 다시 서명·공증한다.

## 재현

```sh
python3 -m venv .build/dmg-design-tools
.build/dmg-design-tools/bin/python -m pip install -r scripts/requirements-dmg.txt
bash scripts/package-dmg.sh --preview
SIGN_IDENTITY='Developer ID Application 인증서 ID' NOTARY_PROFILE=zcre-notary \
  bash scripts/package-dmg.sh --notarize
```

Finder 창을 검토할 때는 DMG를 직접 열어 새로 만들어진 설치 창을 확인한다. 기존 Finder 창에서 마운트 위치로 이동하면 그 창의 도구 모음·크기가 유지될 수 있다.
