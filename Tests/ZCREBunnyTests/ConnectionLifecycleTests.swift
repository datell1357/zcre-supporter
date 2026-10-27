// 검증 분류: 로컬 데이터와 번들 리소스 기반 회귀 테스트. 실제 생성·결제 요청은 보내지 않는다.
import Foundation
import Testing
import ZCRECore
@testable import ZCREBunny

// WebKit 응답이 없어도 제한 시간 후 갱신 대기가 해제되는지 검증한다.
@Test @MainActor func unresponsiveWebKitCannotKeepRefreshWaiting() async {
    let pending = PendingWebSnapshot()
    await #expect(throws: SnapshotError.network) {
        try await pending.value(timeout: .milliseconds(10), start: {})
    }
    // A late WebKit completion after the native deadline must be harmless.
    pending.finish(.success("late result"))
}

// 페이지 이동 취소 이후 늦은 응답이 대기를 다시 완료하지 않는지 검증한다.
@Test @MainActor func cancelledNavigationCompletesBeforeLateWebKitReply() async {
    let pending = PendingWebSnapshot()
    pending.finish(.failure(CancellationError()))
    await #expect(throws: CancellationError.self) {
        try await pending.value { Issue.record("Cancelled evaluation must not start JavaScript") }
    }
    pending.finish(.success("obsolete page"))
}

// 중복 콜백 중 최초 결과만 반영하는지 검증한다.
@Test @MainActor func firstWebKitCompletionWins() async throws {
    let pending = PendingWebSnapshot()
    let value = try await pending.value {
        pending.finish(.success("current page"))
        pending.finish(.success("duplicate callback"))
    }
    #expect(value == "current page")
}

// 이전 70% 크기 설정을 한 번만 새 100% 기준으로 변환하는지 검증한다.
@Test @MainActor func legacySeventyPercentMigratesOnceToNewDefault() {
    let suite = "kr.co.zcre.bunny.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(0.7, forKey: "petScale")
    let first = Preferences(defaults: defaults, domainName: suite)
    #expect(first.petScale == 1)
    first.petScale = 0.8
    #expect(Preferences(defaults: defaults, domainName: suite).petScale == 0.8)
}

// 새 설치에서 사용자가 지정한 새 기본 캐릭터 크기를 사용하는지 검증한다.
@Test @MainActor func newInstallUsesSmallerDefaultCharacter() {
    let suite = "kr.co.zcre.bunny.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.register(defaults: ["petScale": 1.0])
    #expect(Preferences(defaults: defaults, domainName: suite).petScale == 1)
}
