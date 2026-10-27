# 플랫폼 공통 상태 전이 입력

monitor.json은 실제 계정과 무관한 합성 데이터입니다. 각 시나리오는 새 Monitor로 시작합니다.

- at: 현재 조회의 Unix 초. payload는 기존 ReadSnapshot 출력과 같은 형태입니다.
- events: 순서대로 기대하는 completed:<id>, failed:<id>, lowCredits:<소수 잔액>.
- tracked: 정렬된 미완료/상태 미상 ID. 목록에서 잠시 사라져도 유지해야 합니다.
- 낮은 잔액 기준은 50입니다. 새 계정에서는 기준선을 다시 설정합니다.

macOS 검증: sharedWindowsMonitorFixturesMatchMacImplementation 테스트에서 실제 SnapshotDecoder/Monitor를 사용합니다.
Windows도 구현된 디코더/Monitor에 동일 JSON을 입력해 비교해야 하며, 기대값을 복사해서 반환하는 검증은 허용하지 않습니다.
이 테스트는 작업 전이 일부를 검증하며 로그인·UI·실제 서버 응답 검증을 대체하지 않습니다.

`decoder.json`은 잘못된 루트 JSON, 필수 필드 누락·null, 잘못된 소수와 시각을 거절하고 유효한 소수 잔액·작업별 동시 생성 수를 보존하는 13개 입력입니다. invalid 케이스는 처리되지 않은 런타임 예외가 아니라 앱의 invalidResponse 오류로 반환해야 합니다. `sharedWindowsDecoderFixturesMatchMacImplementation`에서 macOS 구현으로 검증합니다.
