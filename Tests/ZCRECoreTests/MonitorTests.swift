// 검증 분류: 로컬 데이터와 번들 리소스 기반 회귀 테스트. 실제 생성·결제 요청은 보내지 않는다.
import Foundation
import Testing
@testable import ZCRECore

private let start = Date(timeIntervalSince1970: 1_700_000_000)
// 실제 서버 작업 대신 고정된 작업 테스트 데이터를 만든다.
private func job(_ id: String = "job-a", _ status: JobStatus, created: Date = start.addingTimeInterval(-60)) -> GenerationJob {
    GenerationJob(id: id, model: "seedance-2.5", mediaType: "video", status: status, createdAt: created)
}
// 계정·시각·잔액을 조절할 수 있는 로컬 스냅샷을 만든다.
private func snapshot(_ jobs: [GenerationJob], available: Decimal = 90, at: Date = start, account: String = "account-a") -> WorkspaceSnapshot {
    WorkspaceSnapshot(workspaceKey: account, workspaceName: "테스트", balance: CreditBalance(total: 100, reserved: 10, available: available), jobs: jobs, fetchedAt: at)
}

// 첫 조회에서 기존 완료 이력과 낮은 잔액을 새 알림으로 보내지 않는지 검증한다.
@Test func firstFetchNeverNotifiesHistoricalCompletionsOrLowBalance() {
    var monitor = Monitor()
    #expect(monitor.ingest(snapshot([job(.succeeded)], available: 10), lowCreditThreshold: 50).isEmpty)
}
// 하나의 완료 전이를 한 번만 알리는지 검증한다.
@Test func completionNotifiesExactlyOnce() {
    var monitor = Monitor()
    _ = monitor.ingest(snapshot([job(.running)]), lowCreditThreshold: 50)
    let done = snapshot([job(.succeeded)], at: start.addingTimeInterval(15))
    #expect(monitor.ingest(done, lowCreditThreshold: 50) == [.completed(job(.succeeded))])
    #expect(monitor.ingest(done, lowCreditThreshold: 50).isEmpty)
}
// 실패를 성공 완료와 구분하는지 검증한다.
@Test func failureIsSeparateFromCompletion() {
    var monitor = Monitor()
    _ = monitor.ingest(snapshot([job(.queued)]), lowCreditThreshold: 50)
    #expect(monitor.ingest(snapshot([job(.failed)]), lowCreditThreshold: 50) == [.failed(job(.failed))])
}
// 조회 사이에 시작하고 끝난 작업의 완료도 감지하는지 검증한다.
@Test func jobsThatFinishBetweenPollsAreDetected() {
    var monitor = Monitor()
    _ = monitor.ingest(snapshot([]), lowCreditThreshold: 50)
    let quick = job("quick", .succeeded, created: start.addingTimeInterval(3))
    #expect(monitor.ingest(snapshot([quick], at: start.addingTimeInterval(15)), lowCreditThreshold: 50) == [.completed(quick)])
}
// 뒤 페이지의 오래된 작업이 새 완료 알림을 만들지 않는지 검증한다.
@Test func oldJobsOnLaterPagesDoNotTriggerAlerts() {
    var monitor = Monitor()
    _ = monitor.ingest(snapshot([]), lowCreditThreshold: 50)
    #expect(monitor.ingest(snapshot([job(.succeeded)], at: start.addingTimeInterval(15)), lowCreditThreshold: 50).isEmpty)
}
// 현재 목록에 없는 미완료 작업을 개별 조회 대상으로 유지하는지 검증한다.
@Test func missingActiveJobIsRetainedForDirectRefresh() {
    var monitor = Monitor()
    _ = monitor.ingest(snapshot([job(.running)]), lowCreditThreshold: 50)
    _ = monitor.ingest(snapshot([]), lowCreditThreshold: 50)
    #expect(monitor.trackedActiveIDs == ["job-a"])
    _ = monitor.ingest(snapshot([job(.cancelled)]), lowCreditThreshold: 50)
    #expect(monitor.trackedActiveIDs.isEmpty)
}
// 계정 전환 시 알림 기준선이 새 계정에 맞춰 초기화되는지 검증한다.
@Test func switchingWorkspaceResetsNotificationBaseline() {
    var monitor = Monitor()
    _ = monitor.ingest(snapshot([job(.running)]), lowCreditThreshold: 50)
    #expect(monitor.ingest(snapshot([job(.succeeded)], account: "account-b"), lowCreditThreshold: 50).isEmpty)
}
// 잔액 임계치 진입 때만 알리고 충전 후 다시 알릴 수 있는지 검증한다.
@Test func lowCreditAlertIsEdgeTriggeredAndRearmsAfterRefill() {
    var monitor = Monitor()
    _ = monitor.ingest(snapshot([]), lowCreditThreshold: 50)
    #expect(monitor.ingest(snapshot([], available: 50), lowCreditThreshold: 50) == [.lowCredits(50)])
    #expect(monitor.ingest(snapshot([], available: 40), lowCreditThreshold: 50).isEmpty)
    _ = monitor.ingest(snapshot([], available: 100), lowCreditThreshold: 50)
    #expect(monitor.ingest(snapshot([], available: 30), lowCreditThreshold: 50) == [.lowCredits(30)])
}
// 알 수 없는 서버 상태를 성공이나 진행 중으로 추정하지 않는지 검증한다.
@Test func unknownStateIsNeitherSuccessNorActive() {
    #expect(JobStatus(serverValue: "brand_new_state") == .unknown)
    #expect(!JobStatus.unknown.isActive)
    #expect(!JobStatus.unknown.isTerminal)
    var monitor = Monitor()
    _ = monitor.ingest(snapshot([job(.unknown)]), lowCreditThreshold: 50)
    #expect(monitor.trackedActiveIDs == ["job-a"])
}
// 현재 지원하는 ZCRE 상태 별칭을 작업 상태에 매핑하는지 검증한다.
@Test func verifiedZCREWebStatesMapToActiveWork() {
    for state in ["received", "validated", "queued_internal"] { #expect(JobStatus(serverValue: state) == .queued) }
    for state in ["submitting_provider", "submitted_provider", "running_provider", "asset_ingesting"] { #expect(JobStatus(serverValue: state) == .running) }
}
// 정상 5초 조회와 최대 지연이 있는 실패 재시도 정책을 검증한다.
@Test func backoffIsBoundedAndAllWorkIsCheckedEveryFiveSeconds() {
    #expect(PollPolicy.delay(activeJobs: 2, failures: 0) == 5)
    #expect(PollPolicy.delay(activeJobs: 0, failures: 0) == 5)
    #expect(PollPolicy.delay(activeJobs: 2, failures: 1) == 30)
    #expect(PollPolicy.delay(activeJobs: 2, failures: 999) == 300)
}
// 소수 잔액과 실제 사용 가능 잔액을 손실 없이 해석하는지 검증한다.
@Test func decoderPreservesDecimalsAndAvailableBalance() throws {
    let data = Data(#"{"workspaceKey":"test","balance":{"total":"100.25","reserved":"10.10","available":"90.15"},"jobs":[]}"#.utf8)
    let result = try SnapshotDecoder.decode(data, now: start)
    #expect(result.balance.available == Decimal(string: "90.15"))
    #expect(CreditBalance.format(result.balance.total) == "100.25")
}
// 웹 요금제 한도만 사용하고 사용량은 API 작업으로 계산하는지 검증한다.
@Test func decoderReadsPlanLimitsButNeverUsesStaleWebUsage() throws {
    let base: [String: Any] = ["workspaceKey": "test", "balance": ["total": "90", "reserved": "0", "available": "90"], "jobs": []]
    // 동시 생성 한도 변형을 주입해 디코더를 실행한다.
    func decode(_ concurrency: [String: Int]?) throws -> WorkspaceSnapshot {
        var payload = base
        payload["concurrency"] = concurrency
        return try SnapshotDecoder.decode(JSONSerialization.data(withJSONObject: payload))
    }
    #expect(try decode(nil).concurrency == nil)
    let usage = ["imagesActive": 2, "imagesLimit": 10, "videosActive": 1, "videosLimit": 6, "totalActive": 3, "totalLimit": 16]
    let result = try decode(usage)
    #expect(result.concurrency?.totalActive == 0)
    #expect(result.concurrency?.imagesActive == 0)
    #expect(result.concurrency?.videosActive == 0)
    #expect(result.concurrency?.imagesLimit == 10)
    var invalid = usage
    invalid["totalLimit"] = 0
    #expect(try decode(invalid).concurrency == nil)
}
// 웹의 오래된 0 사용량이 실제 이미지·영상 작업을 가리지 않는지 검증한다.
@Test func staleZeroWebCounterCannotHideLiveImageAndVideoWork() throws {
    let data = Data(#"{"workspaceKey":"test","balance":{"total":"90","reserved":"10","available":"80"},"jobs":[{"id":"video","model":"topaz-upscale-video-precision","mediaType":"video","status":"submitted_provider","createdAt":"2026-10-25T11:19:00Z"},{"id":"image","model":"gpt-image-2","mediaType":"image","status":"queued_internal","createdAt":"2026-10-25T11:20:00Z"},{"id":"done","model":"seedance-2.5","mediaType":"video","status":"succeeded","createdAt":"2026-10-25T11:00:00Z"}],"concurrency":{"imagesActive":0,"imagesLimit":10,"videosActive":0,"videosLimit":6,"totalActive":0,"totalLimit":16}}"#.utf8)
    let result = try SnapshotDecoder.decode(data)
    #expect(result.activeJobs.count == 2)
    #expect(result.concurrency?.imagesActive == 1)
    #expect(result.concurrency?.videosActive == 1)
    #expect(result.concurrency?.totalActive == result.activeJobs.count)
    #expect(result.concurrency?.imagesLimit == 10)
    #expect(result.concurrency?.videosLimit == 6)
    #expect(result.concurrency?.totalLimit == 16)
}
// 원문 작업 ID 대신 모델·매체·시작 시각으로 완료 작업을 구분하는지 검증한다.
@Test func completionIdentifiesModelMediaAndStartTimeWithoutExposingID() {
    let first = GenerationJob(id: "private-job-a", model: "topaz-upscale-video-precision", mediaType: "video", status: .succeeded, createdAt: start)
    let later = GenerationJob(id: "private-job-b", model: first.model, mediaType: "video", status: .succeeded, createdAt: start.addingTimeInterval(120))
    #expect(first.completionTitle == "Topaz 영상 업스케일 완료")
    #expect(first.completionBubble.hasPrefix("Topaz 영상 업스케일\n"))
    #expect(first.completionBubble.contains(first.startTimeLabel))
    #expect(first.completionBody.contains(first.startTimeLabel))
    #expect(first.completionBubble != later.completionBubble)
    #expect(!first.completionBubble.contains(first.id))
    let image = GenerationJob(id: "image", model: "gpt-image-2", mediaType: "image", status: .succeeded, createdAt: start)
    #expect(image.completionTitle == "GPT Image 2 이미지 완료")
}
// 필수 필드 누락을 0 잔액으로 표시하지 않는지 검증한다.
@Test func decoderRejectsMissingFieldsInsteadOfShowingZero() {
    let data = Data(#"{"workspaceKey":"test","jobs":[]}"#.utf8)
    #expect(throws: SnapshotError.invalidResponse) { try SnapshotDecoder.decode(data) }
}
// 잘못된 소수 문자열을 거부하는지 검증한다.
@Test func decoderRejectsMalformedDecimal() {
    let data = Data(#"{"workspaceKey":"test","balance":{"total":"90oops","reserved":"0","available":"90"},"jobs":[]}"#.utf8)
    #expect(throws: SnapshotError.invalidResponse) { try SnapshotDecoder.decode(data) }
}
// 잘못된 시각 필드를 거부하는지 검증한다.
@Test func decoderRejectsInvalidTimestamp() {
    let data = Data(#"{"workspaceKey":"test","balance":{"total":"90","reserved":"0","available":"90"},"jobs":[{"id":"a","model":"video","status":"running","mediaType":"video","createdAt":"no-date"}]}"#.utf8)
    #expect(throws: SnapshotError.invalidResponse) { try SnapshotDecoder.decode(data) }
}
// 인증·통신 오류가 정상 스냅샷과 구분되는지 검증한다.
@Test func decoderUnderstandsAuthenticationAndTransportErrors() {
    #expect(throws: SnapshotError.authentication) { try SnapshotDecoder.decode(Data(#"{"error":"authentication"}"#.utf8)) }
    #expect(throws: SnapshotError.http(429)) { try SnapshotDecoder.decode(Data(#"{"error":"http","status":429}"#.utf8)) }
}
// 취소 작업을 성공 알림으로 보내지 않는지 검증한다.
@Test func cancelledJobsDoNotProduceSuccessAlerts() {
    var monitor = Monitor()
    _ = monitor.ingest(snapshot([job(.running)]), lowCreditThreshold: 50)
    #expect(monitor.ingest(snapshot([job(.cancelled)]), lowCreditThreshold: 50).isEmpty)
}

// Convenience overload retains explicit request identities in multi-job tests.
// 실제 서버 작업 대신 고정된 작업 테스트 데이터를 만든다.
private func job(_ status: JobStatus) -> GenerationJob { job("job-a", status) }

// 늦게 목록에 나타난 짧은 작업의 완료를 놓치지 않는지 검증한다.
@Test func delayedVisibilityOfAQuickJobDoesNotLoseItsCompletion() {
    var monitor = Monitor()
    _ = monitor.ingest(snapshot([]), lowCreditThreshold: 50)
    _ = monitor.ingest(snapshot([], at: start.addingTimeInterval(5)), lowCreditThreshold: 50)
    let quick = job("delayed", .succeeded, created: start.addingTimeInterval(2))
    #expect(monitor.ingest(snapshot([quick], at: start.addingTimeInterval(10)), lowCreditThreshold: 50) == [.completed(quick)])
    #expect(monitor.ingest(snapshot([quick], at: start.addingTimeInterval(15)), lowCreditThreshold: 50).isEmpty)
}
// 잔액 오류가 작업 완료를 가리거나 잘못된 잔액 알림을 만들지 않는지 검증한다.
@Test func staleCreditsDoNotHideCompletionOrTriggerAFakeCreditAlert() {
    var monitor = Monitor()
    _ = monitor.ingest(snapshot([job(.running)]), lowCreditThreshold: 50)
    let stale = WorkspaceSnapshot(workspaceKey: "account-a", workspaceName: "test",
        balance: CreditBalance(total: 10, reserved: 0, available: 10), jobs: [job(.succeeded)],
        fetchedAt: start.addingTimeInterval(5), balanceFetchedAt: start, balanceIsStale: true)
    #expect(monitor.ingest(stale, lowCreditThreshold: 50) == [.completed(job(.succeeded))])
    #expect(monitor.ingest(snapshot([job(.succeeded)], available: 10, at: start.addingTimeInterval(10)), lowCreditThreshold: 50) == [.lowCredits(10)])
}
// 진행 개수가 같아도 서로 다른 작업의 교체를 감지하는지 검증한다.
@Test func sameActiveCountCanStillCompleteOneJobAndStartAnother() {
    var monitor = Monitor()
    _ = monitor.ingest(snapshot([job(.running)]), lowCreditThreshold: 50)
    let next = snapshot([job(.succeeded), job("second", .running, created: start.addingTimeInterval(2))], at: start.addingTimeInterval(5))
    #expect(next.activeJobs.count == 1)
    #expect(monitor.ingest(next, lowCreditThreshold: 50) == [.completed(job(.succeeded))])
    #expect(monitor.trackedActiveIDs == ["second"])
}
// 작업과 잔액의 갱신 시각·신선도를 각각 해석하는지 검증한다.
@Test func decoderSeparatesJobAndCreditFreshness() throws {
    let data = Data(#"{"workspaceKey":"test","balance":{"total":"90","reserved":"0","available":"90"},"balanceFetchedAt":1700000000000,"balanceIsStale":true,"jobs":[]}"#.utf8)
    let result = try SnapshotDecoder.decode(data, now: start.addingTimeInterval(60))
    #expect(result.fetchedAt == start.addingTimeInterval(60))
    #expect(result.balanceFetchedAt == start)
    #expect(result.balanceIsStale)
}
