// 기능 분류: 명시적 CLI 실행에서만 동작하는 무창·읽기 전용 실계정 점검
import AppKit
import ZCRECore

/// 생성·결제·알림 발송이나 설정 변경 없이 기존 세션과 완료 결과만 확인한다.
@MainActor enum LiveAccountVerification {
    static func run(reportURL: URL) async {
        var checks: [String: Bool] = [:]
        var details: [String: String] = [:]
        let web = WebSession()
        let status = ServiceStatusStore()
        defer { status.stop(); web.clearOutputs(); web.cancelSnapshot(); web.cancelCreatorMetricsRequest(); web.webView.stopLoading() }
        do {
            web.start()
            let deadline = ProcessInfo.processInfo.systemUptime + 45
            var first: WorkspaceSnapshot?
            while ProcessInfo.processInfo.systemUptime < deadline {
                if web.isLoaded {
                    do { first = try await web.snapshot(activeIDs: [], previous: nil); break }
                    catch { details["accountOutcome"] = DiagnosticOutcome.failure(error).rawValue }
                }
                try await Task.sleep(for: .seconds(5))
            }
            guard let first else { throw SnapshotError.authentication }
            details.removeValue(forKey: "accountOutcome")
            checks["authenticatedSnapshot"] = !first.workspaceKey.isEmpty && !first.balanceIsStale
            web.acceptSnapshot(first)
            try await Task.sleep(for: .seconds(5))
            let second = try await web.snapshot(activeIDs: first.activeJobs.map(\.id), previous: first)
            web.acceptSnapshot(second)
            checks["fiveSecondAccountRefresh"] = second.workspaceKey == first.workspaceKey && second.fetchedAt > first.fetchedAt
            // 첫 감지 후 15초는 정산 확인 구간이므로 같은 잔액을 다시 조회하는 것이 정상이다.
            // 해당 구간 이후 작업 변화가 없는 응답에서 캐시 재사용을 확인한다.
            try await Task.sleep(for: .seconds(16))
            let settled = try await web.snapshot(activeIDs: second.activeJobs.map(\.id), previous: second)
            web.acceptSnapshot(settled)
            let sameJobs = second.jobs.map { $0.id + ":" + $0.status.rawValue }.sorted() == settled.jobs.map { $0.id + ":" + $0.status.rawValue }.sorted()
            checks["creditCacheAfterStartupWindow"] = !settled.balanceIsStale && sameJobs && abs(settled.balanceFetchedAt.timeIntervalSince(second.balanceFetchedAt)) < 0.001
            let metrics = CreatorMetricsStore(loader: { key in try await web.creatorMetrics(workspace: key) })
            metrics.setContext(workspace: second.workspaceKey, demo: false)
            await metrics.refresh(manual: true)?.value
            checks["creatorMetrics"] = metrics.snapshot != nil && !metrics.isRefreshing && metrics.errorMessage == nil
            details["creatorChannels"] = String(metrics.snapshot?.accounts.count ?? 0)
            await status.refresh()?.value
            checks["serviceStatus"] = status.snapshot != nil && !status.hasError
            let updates = AppUpdateStore()
            await updates.check(manual: true)
            checks["updateCheck"] = DiagnosticMetrics.shared.snapshot()["updateCheck"]?.lastOutcome == .success
            await updates.check(manual: true)
            checks["manualUpdateRateLimit"] = updates.retryAt != nil && !updates.isChecking
            guard let job = second.jobs.first(where: { $0.status == .succeeded && $0.mediaType == "image" })
                ?? second.jobs.first(where: { $0.status == .succeeded }) else { throw SnapshotError.invalidResponse }
            let outputs = try await web.outputs(for: job.id, workspace: second.workspaceKey)
            checks["completedResultMetadata"] = !outputs.isEmpty
            let cached = try await web.outputs(for: job.id, workspace: second.workspaceKey)
            checks["metadataCache"] = cached.map(\.id) == outputs.map(\.id)
            let refreshed = try await web.outputs(for: job.id, workspace: second.workspaceKey, forceRefresh: true)
            checks["metadataForceRefresh"] = !refreshed.isEmpty
            guard let output = refreshed.first, let source = output.downloadURL else { throw SnapshotError.invalidResponse }
            let temporary = try await ResultTransfer(limit: 64 * 1024 * 1024).fetch(source)
            defer { ResultTransfer.removeTemporary(temporary) }
            let destination = reportURL.deletingLastPathComponent().appendingPathComponent("verified-result." + output.fileExtension)
            let save = Task.detached(priority: .utility) { try ResultTransfer.save(temporary, to: destination) }
            try await save.value
            let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
            let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
            checks["realResultDownloadAndSave"] = size > 0
            details["downloadedBytes"] = String(size)
            if output.kind == "image", let url = output.previewURL {
                let image = try await ResultImageCache.load(url)
                checks["realImagePreviewDecode"] = image.size.width > 0 && image.size.height > 0
            } else { details["imagePreview"] = "notApplicableToSelectedMedia" }
        } catch {
            checks["verificationCompleted"] = false
            details["failureOutcome"] = DiagnosticOutcome.failure(error).rawValue
            if let status = DiagnosticOutcome.httpStatus(error) { details["failureHTTPStatus"] = String(status) }
        }
        checks["noVisibleWindows"] = NSApp.windows.allSatisfy { !$0.isVisible }
        let report: [String: Any] = ["version": AppInfo.version, "build": AppInfo.build,
            "passed": !checks.isEmpty && checks.values.allSatisfy { $0 }, "checks": checks, "details": details,
            "generatedAt": ISO8601DateFormatter().string(from: .now)]
        do {
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: reportURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: reportURL.path)
        } catch { print("liveVerificationReport=FAIL") }
    }
}
