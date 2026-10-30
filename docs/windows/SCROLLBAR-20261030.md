# 설정 스크롤바 다크 테마 · 2026-10-30

## 변경과 범위

소스 커밋: `bf874f19a1649af00f3b075b45c0b898a445255d`.

설정 창에만 `SettingsTheme.xaml`을 로드한다. 흰색 기본 스크롤바 대신 어두운 2픽셀 트랙과 둥근 6픽셀 손잡이를 표시한다. 손잡이는 16픽셀 너비의 입력 영역을 유지하고 최소 높이는 32 DIP이다. 호버 때는 8픽셀로 넓어지고 밝아지며, 드래그 중에는 ZCRE 연녹색을 사용한다. 기본 WPF ScrollBar·Track·Thumb와 페이지 명령을 유지하며 외부 의존성은 추가하지 않았다.

다른 창의 스크롤바, 계정·알림 설정 형식, 이미지·영상 생성 기능은 변경하지 않았다.

## 검증

- 네이티브 빌드: 경고 0, 오류 0.
- 실제 WPF 설정 창의 휠·PageDown 이벤트, 트랙 페이지 명령, 손잡이 드래그 이벤트가 각각 내용 위치를 이동하는 것을 검사했다. ScrollViewer의 접근성 Scroll 패턴도 유지됨을 확인했다. 이 자동 이벤트 검사는 실제 포인터 입력과 구분한다.
- 기존 네이티브 트레이 검사에서 작업 영역 안 프레임, 헤더 캡션 영역, 접근 가능한 닫기 버튼, 높이 360픽셀 창의 스크롤·고정 헤더와 닫기 동작도 통과했다.
- 격리 데모 PID 37160, 실제 설정 창 3411130에서 Orca로 새 화면을 직접 확인했다. 이전 실사용 알림이 겹친 초기 컷은 제외하고 헤더를 마우스로 끌어 x=8, y=8로 옮겼다. 크기는 620×712이다.
- 실제 손잡이를 y=180에서 y=430으로 끌자 내용이 상단의 바탕화면 항목에서 작업 종류별 알림·집중 모드로 이동했다. 닫기 헤더는 고정됐다.
- 실제 휠 입력 후 내용이 추가 이동한 것을 전후 PNG로 확인했다.
- 실제 PageDown 입력(CUA의 X keysym `Next`) 후 접근성에 보고된 스크롤 위치가 약 745.625에서 1081.043으로 이동했고, 뒤이은 실제 PNG에서 계정·앱·디버그 항목이 보였다.
- Orca의 입력 응답은 `synthetic_input / unverified`였다. 성공 판단은 그 응답값에 기대지 않고 실제 전후 화면 변화와 키보드 입력 전후 접근성 값을 함께 확인한 결과다.
- 실제 PNG를 읽기 전용으로 검사해 기본 손잡이 색 `#66707F`의 너비 6픽셀, 드래그 후 호버 색 `#919AA7`의 너비 8픽셀, 트랙 색 `#23262C`를 확인했다.
- 드래그 중 연녹색 프레임 자체를 별도로 촬영하지는 않았다. 실제 드래그 후 호버 컷과 내용 이동을 확인한 범위이며, 전용 스크린리더 앱의 동작까지 검사한 것은 아니다.

## 실제 캡처와 전달

다음 4장은 모두 Orca computer-use Windows provider 1.0.0으로 촬영한 620×712 실제 화면이다. 합성·덧칠·잘라내기·RenderTargetBitmap 대체 없이 원본 PNG를 복사했고, 개인정보가 겹치지 않는 것을 직접 확인했다.

비공개 로컬 폴더: `windows/.local/scene-scrollbar-captures-20261030/`.

| 파일명 | 바이트 | SHA-256 |
| --- | ---: | --- |
| zcre-windows-20261030-scrollbar-01-top.png | 23,524 | `b4a2fa5b32d59c1c834069756d880f3c0209e71088fc893fe9e3142bb259e3b3` |
| zcre-windows-20261030-scrollbar-02-after-drag-hover.png | 21,648 | `15e7296fbb81189246a5e58002fc44d9a6ad0e0ca2d2e69b26afe5e2190c9b01` |
| zcre-windows-20261030-scrollbar-03-after-wheel.png | 22,439 | `313239a7d615e19710010e9d9efd80cab04ba54c7e90371dd1162bfbc2c11939` |
| zcre-windows-20261030-scrollbar-04-after-keyboard.png | 33,381 | `b4e1cc1dc29166742e50fb6b38c7b1eedf849cfecea20a14694ee23f351a758c` |

기존 사용자 Mac Studio로 4개 파일을 Taildrop 전송했으며 CLI 종료 코드 0을 확인했다. Mac의 수신 파일 열기 확인은 Windows에서 수행하지 않았다. 이미지와 비공개 실행 데이터는 Git에 추가하지 않았다.

## 패키지와 종료

`windows/artifacts/ZcreSupporter-scrollbar-20261030/`에 별도의 self-contained win-x64 패키지를 만들었다. 격리 프로필에서 `--demo --software-rendering --show-settings --smoke-test`로 실행해 PID 54280, 종료 코드 0, smoke 통과, 13종 스프라이트 로드를 확인했다. 원본 리소스 32개는 바이트 단위로 일치한다.

| 파일 | SHA-256 |
| --- | --- |
| ZcreSupporter.exe | `d9554fa7b78da7bc508f2c68e658899799958ec40569ee7e3f16116e0276aa57` |
| ZcreSupporter.dll | `a53acaff5f8d6953dc440093c4629ec916806bf5df4b99fb474dde555c6b6ed2` |
| ZcreSupporter.Core.dll | `f4f76ece8e77943ccb557528c9b77fbad53fdd50c3cb268caf879c1533023d52` |

실제 캡처 데모는 Ctrl+Q로 정상 종료했다. 패키지 smoke도 앱의 정상 종료 경로로 종료됐다. 최종 ZCRE 프로세스는 0개이며, 실사용 설정·알림 파일은 비공개 보존본과 바이트 단위로 일치하고 로그인 프로필이 남아 있다. 실사용 계정 연결·생성 요청·공개 푸시·배포는 하지 않았다.
