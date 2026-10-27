// 검증 분류: 이력 갱신 시 새 알림·읽음 상태를 보존하면서 불필요한 배열 변경을 줄인다.
import Foundation
import Testing
import ZCRECore
@testable import ZCREBunny

// 반복 조회에서 최신 30개의 ID·읽음 상태가 그대로 유지되고 오래된 이력이 끼어들지 않는다.
@Test func unchangedHistoryKeepsStableAlertIdentityAndReadState() {
    let base = Date(timeIntervalSince1970: 1_700_000_000)
    let jobs = (0..<80).map { GenerationJob(id: "job-\($0)", model: "model", mediaType: "image", status: .succeeded, createdAt: base.addingTimeInterval(-Double($0))) }
    var first = AlertHistoryArchive.merging([], jobs: jobs, clearedThrough: nil, demo: false)
    #expect(first.count == 30)
    first[0].isRead = false
    let next = AlertHistoryArchive.merging(first, jobs: jobs, clearedThrough: nil, demo: false)
    #expect(next == first)
    #expect(!next[0].isRead)
}

// 지운 이력과 진행 중 작업을 복원하지 않으며 새 완료·실패만 읽은 이력으로 보충한다.
@Test func clearedHistoryAndNewNotificationsSurviveHistoryMerge() {
    let base = Date(timeIntervalSince1970: 1_700_000_000)
    let existing = CompanionAlert(kind: .completed, title: "새 완료", body: "작업", createdAt: base.addingTimeInterval(20), jobKey: AlertHistoryArchive.key("new:succeeded"))
    let jobs = [
        GenerationJob(id: "old", model: "model", mediaType: "image", status: .succeeded, createdAt: base),
        GenerationJob(id: "new", model: "model", mediaType: "image", status: .succeeded, createdAt: base.addingTimeInterval(1)),
        GenerationJob(id: "running", model: "model", mediaType: "image", status: .running, createdAt: base.addingTimeInterval(2)),
        GenerationJob(id: "failed", model: "model", mediaType: "image", status: .failed, createdAt: base.addingTimeInterval(3))
    ]
    let merged = AlertHistoryArchive.merging([existing], jobs: jobs, clearedThrough: base, demo: true)
    #expect(merged.count == 2)
    #expect(merged[0] == existing)
    #expect(merged[1].kind == .failed && merged[1].isRead)
    #expect(merged[1].title == "[미리보기] 작업 실패")
}
