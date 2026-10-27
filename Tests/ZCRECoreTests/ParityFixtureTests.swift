// Windows와 macOS가 같은 입력에 같은 작업 전이 결과를 내는지 확인하는 공유 계약.
import Foundation
import Testing
@testable import ZCRECore

@Test func sharedWindowsMonitorFixturesMatchMacImplementation() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let data = try Data(contentsOf: root.appendingPathComponent("ParityFixtures/monitor.json"))
    let cases = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    for fixture in cases {
        let name = try #require(fixture["name"] as? String)
        let steps = try #require(fixture["steps"] as? [[String: Any]])
        var monitor = Monitor()
        for step in steps {
            let at = try #require(step["at"] as? Double)
            let payload = try #require(step["payload"] as? [String: Any])
            let snapshot = try SnapshotDecoder.decode(JSONSerialization.data(withJSONObject: payload), now: Date(timeIntervalSince1970: at))
            let actual = monitor.ingest(snapshot, lowCreditThreshold: 50).map { event in
                switch event {
                case .completed(let job): "completed:\(job.id)"
                case .failed(let job): "failed:\(job.id)"
                case .lowCredits(let amount): "lowCredits:\(NSDecimalNumber(decimal: amount).stringValue)"
                }
            }
            let expected = try #require(step["events"] as? [String])
            let tracked = try #require(step["tracked"] as? [String])
            #expect(actual == expected, "\(name) at \(at)")
            #expect(monitor.trackedActiveIDs == tracked, "\(name) tracked at \(at)")
        }
    }
}

@Test func sharedWindowsDecoderFixturesMatchMacImplementation() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let cases = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("ParityFixtures/decoder.json"))) as? [[String: Any]])
    for fixture in cases {
        let name = try #require(fixture["name"] as? String)
        let valid = try #require(fixture["valid"] as? Bool)
        let payload = try #require(fixture["payload"])
        let data = try JSONSerialization.data(withJSONObject: payload, options: .fragmentsAllowed)
        if !valid {
            #expect(throws: SnapshotError.invalidResponse, "\(name)") { try SnapshotDecoder.decode(data) }
        } else {
            let snapshot = try SnapshotDecoder.decode(data)
            let available = try #require(fixture["available"] as? String)
            #expect(snapshot.balance.available == Decimal(string: available), "\(name)")
            #expect(snapshot.activeJobs.count == fixture["activeCount"] as? Int, "\(name)")
            if let images = fixture["imagesActive"] as? Int { #expect(snapshot.concurrency?.imagesActive == images) }
            if let videos = fixture["videosActive"] as? Int { #expect(snapshot.concurrency?.videosActive == videos) }
        }
    }
}
