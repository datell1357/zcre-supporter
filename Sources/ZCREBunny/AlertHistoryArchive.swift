// 기능 분류: 로컬 알림 이력 저장 · 계정 분리
import CryptoKit
import Foundation
import ZCRECore

/// 마지막 인증 계정의 이력만 저장하고 원문 계정·작업 ID는 메모리에만 둔다.
struct AlertHistoryArchive: Codable, Equatable {
    var version = 1
    let workspaceHash: String
    let alerts: [CompanionAlert]
    let clearedThrough: Date?

    /// 계정 또는 작업 식별자를 SHA-256으로 바꾸어 원문 식별자를 저장하지 않는다.
    static func key(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// 보관 한도 밖의 옛 작업은 생성·해시 계산 전에 제외한다. 기존 알림의 ID·읽음 상태는 보존한다.
    static func merging(_ existing: [CompanionAlert], jobs: [GenerationJob], clearedThrough: Date?, demo: Bool) -> [CompanionAlert] {
        var result = existing
        var known = Set(existing.compactMap(\.jobKey))
        let oldest = existing.count >= 30 ? existing.map(\.createdAt).min() : nil
        for job in jobs where job.status == .succeeded || job.status == .failed {
            if let cutoff = clearedThrough, job.createdAt <= cutoff { continue }
            if let oldest, job.createdAt < oldest { continue }
            let jobKey = key("\(job.id):\(job.status.rawValue)")
            guard known.insert(jobKey).inserted else { continue }
            let completed = job.status == .succeeded
            result.append(CompanionAlert(kind: completed ? .completed : .failed,
                title: (demo ? "[미리보기] " : "") + (completed ? "작업 완료" : "작업 실패"),
                body: job.displayName, createdAt: job.createdAt, isRead: true, source: .workHistory, jobKey: jobKey))
        }
        result.sort { $0.createdAt > $1.createdAt }
        return Array(result.prefix(30))
    }

    private static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "kr.co.zcre.bunny.prototype", isDirectory: true)
            .appendingPathComponent("RecentAlerts.json")
    }

    /// 파일 크기·버전·계정 해시가 유효한 경우에만 로컬 이력을 복원한다.
    static func load(workspaceHash: String) -> AlertHistoryArchive? {
        guard let data = try? Data(contentsOf: fileURL), data.count <= 256_000,
              let archive = try? JSONDecoder().decode(Self.self, from: data),
              archive.version == 1, archive.workspaceHash == workspaceHash else { return nil }
        return archive
    }

    /// 소유자 전용 파일 권한으로 이력을 원자적으로 교체하고 저장 성공 여부를 반환한다.
    func save() -> Bool {
        do {
            let directory = Self.fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            let data = try JSONEncoder().encode(self)
            try data.write(to: Self.fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.fileURL.path)
            return true
        } catch { return false }
    }

    /// 로컬 이력 파일만 제거한다. 서버의 알림이나 작업 이력은 삭제하지 않는다.
    static func remove() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
