import Testing
import Foundation
@testable import ZCREBunny

@Suite @MainActor struct CreatorMetricsTests {
    private func sample() throws -> CreatorMetrics {
        try CreatorMetrics.decode(Data(#"{"totalFollowers":100,"change7d":null,"updatedAt":"2026-11-08T00:00:00.000Z","collectionPaused":false,"accounts":[{"platform":"instagram","handle":"example","followers":100,"change7d":-2,"observedAt":null,"status":"ok","derivedAvailable":true,"daily":[{"day":"2026-11-08","followers":100}],"trendUnavailable":false}]}"#.utf8))
    }
    @Test func preservesUnavailableAndNegativeChanges() throws {
        let value = try sample()
        #expect(value.change7d == nil)
        #expect(value.accounts[0].change7d == -2)
        #expect(value.accounts[0].observedAt == nil)
        #expect(value.updatedAt != nil)
    }
    @Test func reopeningUsesCacheButManualRefreshCanFetchEarlier() async throws {
        var clock: TimeInterval = 0; var calls = 0
        let value = try sample()
        let store = CreatorMetricsStore(uptime: { clock }, loader: { _ in calls += 1; return value })
        store.setContext(workspace: "a", demo: false)
        let first = store.refresh(); let duplicate = store.refresh()
        await first?.value; await duplicate?.value
        #expect(calls == 1)
        let checkedAt = store.lastCheckedAt
        #expect(checkedAt != nil)
        store.stop(); clock = 59
        #expect(store.refresh(manual: true) == nil)
        clock = 60
        await store.observeRefreshDeadline()
        #expect(store.refreshDeadline == nil)
        #expect(store.canRefresh)
        #expect(store.refresh() == nil)
        await store.refresh(manual: true)?.value
        #expect(calls == 2)
        clock = 659
        #expect(store.refresh() == nil)
        clock = 660
        await store.refresh()?.value
        #expect(calls == 3)
        #expect(store.snapshot?.updatedAt == value.updatedAt)
    }
    @Test func noContextOrDemoMakesNoRequests() async throws {
        var calls = 0; let value = try sample()
        let store = CreatorMetricsStore(loader: { _ in calls += 1; return value })
        #expect(store.refresh() == nil)
        store.setContext(workspace: "demo", demo: true)
        #expect(store.refresh() == nil)
        #expect(calls == 0)
    }
    @Test func rateLimitCannotBeBypassedByReopening() async {
        var clock: TimeInterval = 0; var calls = 0
        let store = CreatorMetricsStore(uptime: { clock }, loader: { _ in calls += 1; throw CreatorMetricsHTTPError(status: 429, retryAfter: 120) })
        store.setContext(workspace: "a", demo: false)
        await store.refresh()?.value
        store.stop(); clock = 119
        #expect(store.refresh(manual: true) == nil)
        clock = 120
        await store.refresh(manual: true)?.value
        #expect(calls == 2)
        #expect(store.errorMessage != nil)
    }
    @Test func failedRefreshKeepsLastSuccessfulDataAndCheckTime() async throws {
        let value = try sample()
        var clock: TimeInterval = 0; var calls = 0
        let store = CreatorMetricsStore(uptime: { clock }, loader: { _ in
            calls += 1
            if calls > 1 { throw CreatorMetricsHTTPError(status: 503, retryAfter: 60) }
            return value
        })
        store.setContext(workspace: "a", demo: false)
        await store.refresh()?.value
        let checkedAt = store.lastCheckedAt
        clock = 600
        await store.refresh()?.value
        #expect(store.snapshot == value)
        #expect(store.lastCheckedAt == checkedAt)
        #expect(store.errorMessage != nil)
        clock = 660
        #expect(store.refresh() == nil)
        #expect(store.canRefresh)
    }
    @Test func contextChangeClearsCacheAndDropsLateResponses() async throws {
        let value = try sample()
        var continuation: CheckedContinuation<CreatorMetrics, Never>?
        let store = CreatorMetricsStore(loader: { _ in await withCheckedContinuation { continuation = $0 } })
        store.setContext(workspace: "a", demo: false)
        let pending = store.refresh()
        while continuation == nil { await Task.yield() }
        store.setContext(workspace: "b", demo: false)
        continuation?.resume(returning: value)
        await pending?.value
        #expect(store.snapshot == nil)
        #expect(!store.isRefreshing)
        #expect(store.canRefresh)
    }
    @Test func closingStopsVisibleRefreshAndDiscardsInFlightResponse() async throws {
        let value = try sample()
        var continuation: CheckedContinuation<CreatorMetrics, Never>?
        let store = CreatorMetricsStore(loader: { _ in await withCheckedContinuation { continuation = $0 } })
        store.setContext(workspace: "a", demo: false)
        let visible = Task { await store.refreshWhileVisible() }
        while continuation == nil { await Task.yield() }
        store.stop()
        continuation?.resume(returning: value)
        await visible.value
        #expect(store.snapshot == nil)
        #expect(!store.isRefreshing)
    }
    @Test func hidingCancelsAndLateResponseCannotUpdateCache() async throws {
        let value = try sample()
        var continuation: CheckedContinuation<CreatorMetrics, Never>?
        let store = CreatorMetricsStore(loader: { _ in await withCheckedContinuation { continuation = $0 } })
        store.setContext(workspace: "a", demo: false)
        let pending = store.refresh()
        while continuation == nil { await Task.yield() }
        store.stop(); continuation?.resume(returning: value)
        await pending?.value
        #expect(store.snapshot == nil)
    }
}
