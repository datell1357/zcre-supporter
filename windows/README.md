# ZCRE 서포터 · Windows

Windows 11 x64를 목표로 한 .NET 8 WPF + WebView2 이식판입니다. 현재 실기 검증은 Windows 10 IoT Enterprise LTSC 2021 build 19044에서 진행하며, Windows 11 기능 동등성 완료로 표시하지 않습니다.

## 개발 실행

```text
python windows/build.py test
python windows/build.py build
python windows/run.py --demo --data-dir C:\absolute\workspace\test-data
```

`--demo`는 가상 잔액/작업만 사용합니다. 생성 API를 호출하지 않습니다. 실제 계정 확인은 `--demo` 없이 실행하고 앱의 **ZCRE 계정 연결**에서 사용자가 직접 로그인합니다. 외부 브라우저 쿠키/토큰을 가져오지 않습니다. `--data-dir`은 테스트 격리용이며 생략 시 `%LOCALAPPDATA%\ZCRE Supporter`를 사용합니다.

개발용 실행파일이 사용자별 .NET 런타임을 못 찾으면 `run.py`를 사용합니다. 배포용은 `python windows/build.py publish`로 런타임 포함 x64 폴더를 만듭니다. WebView2 Evergreen Runtime은 별도 필요합니다. 이 저장소는 설치 프로그램을 자동 실행하지 않습니다.

## 기능과 Windows 대응

- 투명 지크 창, 8방향 산책/드래그, JSON 시트 속도, 완료/실패/작업/인사 모션, 원형 도구 메뉴.
- 작업 5초 / 크레딧 60초 및 상태 변경 후 15초 정산 확인은 원본 JavaScript 그대로 사용합니다. 네이티브 타임아웃, 단일 요청, 세대 번호와 ACK를 추가합니다.
- 3열 현황판, 작업 기록·결과 재생/명시적 저장, 공개 서비스 상태 60초 캐시/ETag/재시도.
- 최신 10개/상세 30개 알림, 계정/작업 ID 해시 보관, 작업 종류 필터, 자정을 넘는 집중 일정.
- 트레이는 잔액을 툴팁/현황판에 표시합니다. Windows 기본 트레이가 아이콘 옆 임의 텍스트를 지원하지 않는 차이가 있습니다.
- 시스템 알림은 Windows Shell 알림을 사용합니다. 알림 소리 꺼짐은 `NIIF_NOSOUND`로 전달합니다. 지크 숨김 배너는 비활성 창이며 포커스를 가져오지 않습니다.
- 효과음은 번들 WAV만 사용합니다. Core Audio 세션/피크를 읽어 타자음을 양보하며, 오디오 내용을 캡처하거나 장치 음량을 바꾸지 않습니다.
- 시작 프로그램 기본은 꺼짐입니다. 설정에서 명시적으로 선택할 때 HKCU Run 항목을 변경하며 대상/실행파일을 확인하는 대화상자를 표시합니다.
- `zcrenext`는 로컬 디버그 코드이며 계정 인증정보가 아닙니다. 활성화 상태는 저장하지 않습니다.

키보드: `Ctrl+,` 설정, `Ctrl+H` 상세 현황, `Ctrl+R` 갱신, `Ctrl+D` 미리보기/미리보기 완료, `Ctrl+Q` 앱 종료. 설정의 코드 입력 후 `Alt+D`로 디버그를 활성화할 수 있습니다.

결과 창에서 `Ctrl+S`는 첫 결과의 저장 대화상자를 엽니다. 디버그 활성화 후 설정에서 `Ctrl+M`으로 모션 테스트를 열 수 있습니다. 모션 테스트에서는 `Ctrl+1`~`Ctrl+8`이 8방향 이동, `Ctrl+L/R`이 좌우 잡힘, `Ctrl+W`가 작업, `Ctrl+C/F`가 완료/실패이며 Esc는 중지입니다.

첫 실행은 현황판을 표시하고, 이후 실행은 트레이에서 시작합니다. `--show-dashboard`로 현황판, `--connect`로 계정 연결 창을 명시적으로 열 수 있습니다. 이미 실행 중이면 두 번째 실행은 기존 현황판만 표시합니다.

## 검증과 패키징

[구현/검증 상태](../docs/windows/IMPLEMENTATION.md)와 [24개 판정 기준](../docs/windows/PARITY.md)을 참조하세요. 로그인/유료 생성/장시간/다중 DPI 등 미검증 항목을 자동 검사 결과로 대체하지 않습니다.

빌드 산출물·`.local`·WebView2 사용자 폴더는 Git/배포에서 제외합니다. macOS 원본 소스 및 리소스는 변경하지 않습니다. 코드 서명과 SmartScreen 평판은 아직 제공하지 않는 개발 빌드입니다.
