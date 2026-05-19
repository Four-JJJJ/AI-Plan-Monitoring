import OhMyUsageDomain
import Foundation
import XCTest
@testable import OhMyUsage

@MainActor
final class CountdownFormatterTests: XCTestCase {
    func testNilTargetUsesPlaceholder() {
        let text = CountdownFormatter.text(
            to: nil,
            now: Date(timeIntervalSince1970: 1_000),
            placeholder: "--:--:--",
            language: .zhHans
        )
        XCTAssertEqual(text, "--:--:--")
    }

    func testPastTargetClampsToZero() {
        let now = Date(timeIntervalSince1970: 1_000)
        let target = now.addingTimeInterval(-30)
        XCTAssertEqual(
            CountdownFormatter.text(to: target, now: now, placeholder: "-", language: .zhHans),
            "0时0分"
        )
    }

    func testBoundarySecondsFormatting() {
        let now = Date(timeIntervalSince1970: 10_000)
        let cases: [(TimeInterval, String)] = [
            (0, "0时0分"),
            (1, "0时0分"),
            (59, "0时0分"),
            (60, "0时1分"),
            (3_599, "0时59分"),
            (3_600, "1时0分"),
            (86_399, "23时59分"),
            (86_400, "1天0时")
        ]

        for (offset, expected) in cases {
            let target = now.addingTimeInterval(offset)
            XCTAssertEqual(
                CountdownFormatter.text(to: target, now: now, placeholder: "-", language: .zhHans),
                expected
            )
        }
    }

    func testDayAndHourFormattingForLongCountdown() {
        let now = Date(timeIntervalSince1970: 20_000)
        let target = now.addingTimeInterval(TimeInterval(145 * 3_600 + 32 * 60 + 40))
        XCTAssertEqual(
            CountdownFormatter.text(to: target, now: now, placeholder: "-", language: .zhHans),
            "6天1时"
        )
    }

    func testHourAndMinuteFormattingWhenUnderOneDay() {
        let now = Date(timeIntervalSince1970: 25_000)
        let target = now.addingTimeInterval(TimeInterval(23 * 3_600 + 54 * 60 + 20))
        XCTAssertEqual(
            CountdownFormatter.text(to: target, now: now, placeholder: "-", language: .zhHans),
            "23时54分"
        )
    }

    func testEnglishDayAndHourFormattingForLongCountdown() {
        let now = Date(timeIntervalSince1970: 20_000)
        let target = now.addingTimeInterval(TimeInterval(95 * 3_600 + 32 * 60 + 40))
        XCTAssertEqual(
            CountdownFormatter.text(to: target, now: now, placeholder: "-", language: .en),
            "3 d 23 h"
        )
    }

    func testEnglishHourAndMinuteFormattingWhenUnderOneDay() {
        let now = Date(timeIntervalSince1970: 25_000)
        let target = now.addingTimeInterval(TimeInterval(23 * 3_600 + 54 * 60 + 20))
        XCTAssertEqual(
            CountdownFormatter.text(to: target, now: now, placeholder: "-", language: .en),
            "23 h 54 m"
        )
    }

    func testEnglishPastTargetClampsToZero() {
        let now = Date(timeIntervalSince1970: 1_000)
        let target = now.addingTimeInterval(-30)
        XCTAssertEqual(
            CountdownFormatter.text(to: target, now: now, placeholder: "-", language: .en),
            "0 h 0 m"
        )
    }

    func testMenuCountdownTextUsesSharedFormatterForChinese() {
        let now = Date(timeIntervalSince1970: 30_000)
        let offset = TimeInterval(17_603)
        let target = now.addingTimeInterval(offset)
        XCTAssertEqual(
            MenuContentView.countdownText(to: target, now: now, language: .zhHans),
            CountdownFormatter.text(to: target, now: now, placeholder: "-", language: .zhHans)
        )
        XCTAssertEqual(MenuContentView.countdownText(to: nil, now: now, language: .zhHans), "-")
    }

    func testMenuCountdownTextUsesSharedFormatterForEnglish() {
        let now = Date(timeIntervalSince1970: 30_000)
        let offset = TimeInterval(431_603)
        let target = now.addingTimeInterval(offset)
        XCTAssertEqual(
            MenuContentView.countdownText(to: target, now: now, language: .en),
            CountdownFormatter.text(to: target, now: now, placeholder: "-", language: .en)
        )
        XCTAssertEqual(MenuContentView.countdownText(to: nil, now: now, language: .en), "-")
    }

    func testSettingsCountdownTextUsesSharedFormatterForChinese() {
        let now = Date(timeIntervalSince1970: 40_000)
        let target = now.addingTimeInterval(84 * 3_600)
        XCTAssertEqual(
            SettingsCountdownPresenter.codexCountdownText(to: target, now: now, language: .zhHans),
            CountdownFormatter.text(to: target, now: now, placeholder: "--:--:--", language: .zhHans)
        )
        XCTAssertEqual(SettingsCountdownPresenter.codexCountdownText(to: nil, now: now, language: .zhHans), "--:--:--")
    }

    func testSettingsCountdownTextUsesSharedFormatterForEnglish() {
        let now = Date(timeIntervalSince1970: 40_000)
        let target = now.addingTimeInterval(84 * 3_600)
        XCTAssertEqual(
            SettingsCountdownPresenter.codexCountdownText(to: target, now: now, language: .en),
            CountdownFormatter.text(to: target, now: now, placeholder: "--:--:--", language: .en)
        )
        XCTAssertEqual(SettingsCountdownPresenter.codexCountdownText(to: nil, now: now, language: .en), "--:--:--")
    }

    func testResetTrustLabelsReflectSourceAndFreshness() {
        let now = Date(timeIntervalSince1970: 50_000)
        let official = UsageQuotaWindow(
            id: "official",
            title: "5h",
            remainingPercent: 80,
            usedPercent: 20,
            resetAt: now.addingTimeInterval(3_600),
            kind: .session,
            resetSource: .official,
            observedAt: now,
            confidence: .confirmed
        )
        let local = UsageQuotaWindow(
            id: "local",
            title: "5h",
            remainingPercent: 80,
            usedPercent: 20,
            resetAt: now.addingTimeInterval(3_600),
            kind: .session,
            resetSource: .localEstimate,
            observedAt: now,
            confidence: .estimated
        )

        XCTAssertEqual(
            CountdownFormatter.resetTrustLabel(for: official, snapshotFreshness: .live, language: .zhHans),
            "官方确认"
        )
        XCTAssertEqual(
            CountdownFormatter.resetTrustLabel(for: local, snapshotFreshness: .live, language: .zhHans),
            "本地估算"
        )
        XCTAssertEqual(
            CountdownFormatter.resetTrustLabel(for: official, snapshotFreshness: .cachedFallback, language: .zhHans),
            "待刷新"
        )
        XCTAssertEqual(
            CountdownFormatter.textWithTrustLabel(
                for: official,
                snapshotFreshness: .live,
                now: now,
                placeholder: "-",
                language: .zhHans
            ),
            "1时0分"
        )
    }
}
