# 설정 창 테마 프레임 · 실제 화면 검증

## 변경

소스 커밋: `7e65200f6c528e2b68a0fa926ddd0b26c8465370`.

설정 창의 Windows 기본 제목 표시줄을 없애고 ZCRE 색상의 얇은 테두리·둥근 모서리·어두운 헤더를 적용했다. 헤더의 닫기 버튼은 접근성 이름과 키보드 포커스를 제공하며 `Esc` 닫기도 구현했다. WPF `WindowChrome`의 캡션 영역으로 창을 이동하고 가장자리로 크기를 조절한다. 닫기 헤더는 내용 스크롤과 분리되어 고정된다. 설정 외의 일반 상세·결과 창은 기존 프레임을 유지한다.

설정 내용의 수직 스크롤을 명시하고 최소 크기를 320×240 DIP로 지정했다. 기존 작업 영역 안으로의 창 배치를 유지한다. 계정·알림 설정 형식과 연결 동작은 변경하지 않았다.

## 검증 결과

- 변경 전 네이티브 검사에서 기본 제목 표시줄이 남아 실패하는 것을 확인한 후 수정했다.
- 최종 네이티브 빌드: 경고 0, 오류 0.
- 네이티브 창 검사: 설정 창의 `WindowStyle.None`, 불투명 클라이언트, 실제 작업 영역 안 프레임, 헤더의 `HTCAPTION`, 닫기 버튼의 `HTCLIENT`·접근성 이름·포커스 가능 여부를 확인했다.
- 높이를 360픽셀로 줄인 실제 WPF 설정 창에서 내용이 끝까지 스크롤되고 닫기 헤더가 고정되는 것을 검사했다. 닫기 버튼의 실제 WPF 클릭 이벤트가 설정 창을 닫는 것도 확인했다. 이 자동 이벤트 검사는 실제 포인터 클릭과 구분한다.
- 기존 네이티브 복구 검사 통과: WebView2 초기화 실패 재시도, 설정 저장 실패 안내의 실제 설정 창 표시, 복구 후 안내 해제 및 저장 유지.
- 실제 데모 PID 32756에서 Orca 마우스 드래그로 새 헤더를 잡아 창을 x=202에서 x=8로 이동했다. y=8, 620×712 크기가 유지되었다.
- 실제 마우스 휠 요청은 `unverified / synthetic_input`이었고 화면 변화가 없었다. 키보드 Tab·스크롤바 접근성 값 변경도 스크롤 성공으로 인정하지 않았다. 후자는 `focus element before setting value: 대상 요소가 포커스를 받을 수 없습니다. (0x80131509)`를 반환했다.
- 마지막 `Ctrl+Q` 요청 후 해당 데모 프로세스가 사라졌음을 별도 확인했다. 기본 캡처 도구도 일반 창 닫기로 종료되어 남지 않았다. 실제 `Esc`·닫기 버튼 포인터 클릭을 각각 검증했다고 주장하지 않는다.

## 실제 캡처와 비공개 전달

새 설정 창 실제 캡처 1장을 확보했다. 실제 기존 계정 알림이 겹치는 최초 컷은 제외하고, 창을 왼쪽으로 이동한 후 개인정보가 겹치지 않는 컷만 저장·전송했다. 가공·합성·RenderTargetBitmap 출력이 아니다.

| 항목 | 값 |
| --- | --- |
| 로컬 파일 | `windows/.local/scene-themed-captures-20261030/01-settings-themed.png` |
| 크기 | 620×712, 26,129바이트 |
| SHA-256 | `fa205efba2dd6f2da0d4e2b2018a54e8197ea4c5d428c698773d664db56dd63a` |
| 공식 도구 | Orca computer-use Windows provider 1.0.0 |
| Taildrop 파일명 | `zcre-windows-20261030-02-settings-themed.png` |

기존 사용자 Mac Studio로 Taildrop 전송 종료 코드 0을 확인했다. Mac의 최종 저장 위치와 열기는 Windows에서 확인하지 않았다. 이미지와 비공개 상세 로그는 Git에 추가하지 않았다.

현황판과 지크의 새 실제 PNG는 확보하지 못했다. 네이티브 검사의 현황 창 가시성·좌표 확인을 실제 화면 캡처로 표현하지 않는다. 이번 과정에서 실제 트레이 아이콘 클릭, 지크 메뉴 상호작용, 지크 드래그를 검증한 것도 아니다.

## 전체 화면 경로 확인과 오류

사용자가 이번 캡처에 한해 `C:\Windows\System32\SnippingTool.exe` 실행과 저장소 내부 저장을 추가 승인했다. 최초 앱 승인 대기 시간 초과 후 승인된 실행이 성공했고, 설치·권한·보안 설정 변경은 없었다.

- 공식 Orca의 `computer --help`, `computer get-app-state --help`, capabilities를 확인했다. 노출된 캡처는 app/window 대상이며 모니터 대상 명령·옵션은 없다. provider의 native menu·window focus 지원도 false였다.
- Windows 기본 캡처 도구에서 `전체 화면 캡처(A)` 메뉴를 실제로 확인했다. 메뉴 선택 요청 후에도 사각형 모드 표시가 남아 전체 화면 선택 성공으로 인정하지 않았다. 사각형 캡처 시작 상태는 취소했다.
- Sky의 기본 캡처 도구 창 캡처는 `window capture timed out: timed out waiting on channel`을 반환했다.
- 메뉴에 대한 직접 키보드 요청은 `window_not_focused: keyboard input requires the target window to be focused; retry with --restore-window`를 반환했다.
- 안내된 복구를 한 번 시도한 결과는 `accessibility_error: "1"개의 인수가 있는 "FromHandle"을(를) 호출하는 동안 예외가 발생했습니다. "인식할 수 없는 오류입니다."`였다. 같은 실패 경로를 반복하지 않았다.
- CUA 메뉴 창 선택은 `window id 28836132 was not found`였다. 원래 캡처 도구 창은 목록에 남아 있었으나 transient 메뉴를 입력 대상으로 잡지 못했다.
- Windows 공식 제어 API 문서를 다시 확인했다. `pressKey`는 키 입력을 제공하지만, 현재 노출된 문서에는 Print Screen의 클립보드 이미지를 PNG 파일로 내보내는 API 또는 저장 절차가 없다. Print Screen으로 실제 파일을 확보했다고 주장하지 않는다.

번들 `computer-use` 스킬은 `SKILL.md`에서 읽도록 지정한 `docs/guidance.md`에 “Use only the Computer Use JS APIs for Windows app automation.”을 명시한다. CUA 런타임 문서도 다른 제어 기술은 사용자의 구체적 요청이 있을 때만 허용한다. 이번에 명시적으로 승인된 Orca·Windows 기본 캡처 도구 경로는 사용했지만, 권한 변경이나 별도의 PowerShell/Win32 화면 제어·캡처 래퍼를 추가하지 않았다. 제약은 도구 문서와 실제 오류의 범위로 한정하며 Windows 자체에서 전체 화면 캡처가 불가능하다는 뜻은 아니다.

## 패키지와 종료 상태

`windows/artifacts/ZcreSupporter-themed-20261030/`에 별도의 self-contained win-x64 패키지를 publish했다. 앞선 패키지와 실사용 데이터는 보존했다.

새 패키지를 격리 프로필로 `--demo --software-rendering --show-settings --smoke-test` 실행했다. PID 32664, 종료 코드 0, smoke 통과, 13종 스프라이트 로드, 원본 리소스 32개 바이트 일치를 확인했다. 자동 정상 종료 후 ZCRE 프로세스는 0개였다. 실사용 설정·알림 파일은 기존 비공개 보존본과 바이트 단위로 일치하며 로그인 프로필도 남아 있다.

| 파일 | SHA-256 |
| --- | --- |
| ZcreSupporter.exe | `bdbcaf63bd2670da1c50446c0c71c92ef32c853856811c6fabd80939074b6fc9` |
| ZcreSupporter.dll | `dc45c3ad06cfaf9c3a068ca8ed46c294e512c6b26cfc5dc067726df968469ccc` |
| ZcreSupporter.Core.dll | `29396c0b8b493818c936815ac87a0c7ed37bf49444641900f941d40a60c7889d` |

로컬 `feature/windows-port`만 변경했다. 공개 푸시·배포·생성 요청은 수행하지 않았다. 현황판·지크의 실제 캡처와 포인터 동작 검증은 여전히 미완료다.
