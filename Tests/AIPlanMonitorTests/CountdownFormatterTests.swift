import Foundation
import XCTest
@testable import AIPlanMonitor

@MainActor
final class CountdownFormatterTests: XCTestCase {
    func testNilTargetUsesPlaceholder() {
        let text = CountdownFormatter.text(
            to: nil,
            now: Date(timeIntervalSince1970: 1_000),
            placeholder: "--:--:--"
        )
        XCTAssertEqual(text, "--:--:--")
    }

    func testPastTargetClampsToZero() {
        let now = Date(timeIntervalSince1970: 1_000)
        let target = now.addingTimeInterval(-30)
        XCTAssertEqual(
            CountdownFormatter.text(to: target, now: now, placeholder: "-"),
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
                CountdownFormatter.text(to: target, now: now, placeholder: "-"),
                expected
            )
        }
    }

    func testDayAndHourFormattingForLongCountdown() {
        let now = Date(timeIntervalSince1970: 20_000)
        let target = now.addingTimeInterval(TimeInterval(145 * 3_600 + 32 * 60 + 40))
        XCTAssertEqual(
            CountdownFormatter.text(to: target, now: now, placeholder: "-"),
            "6天1时"
        )
    }

    func testHourAndMinuteFormattingWhenUnderOneDay() {
        let now = Date(timeIntervalSince1970: 25_000)
        let target = now.addingTimeInterval(TimeInterval(23 * 3_600 + 54 * 60 + 20))
        XCTAssertEqual(
            CountdownFormatter.text(to: target, now: now, placeholder: "-"),
            "23时54分"
        )
    }

    func testMenuCountdownTextUsesSharedFormatter() {
        let now = Date(timeIntervalSince1970: 30_000)
        let target = now.addingTimeInterval(4 * 3_600 + 53 * 60 + 23)
        XCTAssertEqual(
            MenuContentView.countdownText(to: target, now: now),
            CountdownFormatter.text(to: target, now: now, placeholder: "-")
        )
        XCTAssertEqual(MenuContentView.countdownText(to: nil, now: now), "-")
    }

    func testSettingsCountdownTextUsesSharedFormatter() {
        let now = Date(timeIntervalSince1970: 40_000)
        let target = now.addingTimeInterval(84 * 3_600)
        XCTAssertEqual(
            SettingsView.codexCountdownText(to: target, now: now),
            CountdownFormatter.text(to: target, now: now, placeholder: "--:--:--")
        )
        XCTAssertEqual(SettingsView.codexCountdownText(to: nil, now: now), "--:--:--")
    }
}
