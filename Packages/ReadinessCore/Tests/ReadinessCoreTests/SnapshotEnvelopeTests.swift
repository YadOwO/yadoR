import Foundation
import Testing
@testable import ReadinessCore

struct SnapshotEnvelopeTests {
    @Test func transportRoundTripKeepsAssessmentAndSourceTimes() throws {
        var snapshot = ReadinessFixtures.snapshot(at: Date(timeIntervalSince1970: 1_790_000_000))
        snapshot.isDemo = false
        let envelope = SnapshotEnvelope(origin: "phone", revision: 12, fingerprint: "input-a", snapshot: snapshot)
        let decoded = try JSONDecoder().decode(SnapshotEnvelope.self, from: JSONEncoder().encode(envelope))
        #expect(decoded == envelope)
        #expect(decoded.isValid)
        #expect(decoded.snapshot.dataThrough != decoded.snapshot.generatedAt)
    }

    @Test func oldContextCannotReplaceClearTombstone() {
        var snapshot = ReadinessFixtures.snapshot()
        snapshot.isDemo = false
        let old = SnapshotEnvelope(origin: "phone", revision: 12, fingerprint: "a", snapshot: snapshot)
        let cleared = SnapshotEnvelope(origin: "phone", revision: 13, fingerprint: nil, snapshot: .empty())
        #expect(cleared.supersedes(old))
        #expect(!old.supersedes(cleared))
        #expect(!old.supersedes(old))
    }

    @Test func transportRejectsDemoAndInvalidScores() {
        var envelope = SnapshotEnvelope(origin: "phone", revision: 1, fingerprint: "a", snapshot: ReadinessFixtures.snapshot())
        #expect(!envelope.isValid)
        envelope.snapshot.isDemo = false
        envelope.snapshot.score = 11
        #expect(!envelope.isValid)
        envelope.snapshot.score = 0
        #expect(envelope.isValid)
        envelope.snapshot.status = .missingData
        #expect(!envelope.isValid)
    }

    @Test func aRetiredPhoneCannotReplaceItsSuccessor() throws {
        let original = SnapshotEnvelope(origin: "old-phone", revision: 20, fingerprint: nil, snapshot: .empty())
        let replacement = SnapshotEnvelope(origin: "new-phone", revision: 1, fingerprint: nil, snapshot: .empty())
        let accepted = try #require(replacement.accepted(after: original))
        #expect(accepted.retiredOrigins?.contains("old-phone") == true)
        var delayed = original
        delayed.revision = 21
        #expect(delayed.accepted(after: accepted) == nil)
        var next = replacement
        next.revision = 2
        #expect(next.accepted(after: accepted)?.retiredOrigins == accepted.retiredOrigins)
    }

    @Test func nextDayHidesScoreAndFactorValuesAcrossDST() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 10)))
        var snapshot = ReadinessFixtures.snapshot(at: date)
        snapshot.day = calendar.startOfDay(for: date)
        snapshot.timeZoneIdentifier = calendar.timeZone.identifier
        let nextDay = try #require(calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)))
        let visible = snapshot.visible(at: nextDay, calendar: calendar)
        #expect(visible.status == .missingData)
        #expect(visible.score == nil)
        #expect(visible.factors.isEmpty)
        #expect(visible.generatedAt == snapshot.generatedAt)
        #expect(snapshot.visible(at: date, calendar: calendar).score == snapshot.score)
    }
}
