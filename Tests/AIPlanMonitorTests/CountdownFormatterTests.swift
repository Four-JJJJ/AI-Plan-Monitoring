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
            "00:00:00"
        )
    }

    func testBoundarySecondsFormatting() {
        let now = Date(timeIntervalSince1970: 10_000)
        let cases: [(TimeInterval, String)] = [
            (0, "00:00:00"),
            (1, "00:00:01"),
            (59, "00:00:59"),
            (60, "00:01:00"),
            (3_599, "00:59:59"),
            (3_600, "01:00:00")
        ]

        for (offset, expected) in cases {
            let target = now.addingTimeInterval(offset)
            XCTAssertEqual(
                CountdownFormatter.text(to: target, now: now, placeholder: "-"),
                expected
            )
        }
    }

    func testLargeHourValueIsNotTruncated() {
        let now = Date(timeIntervalSince1970: 20_000)
        let target = now.addingTimeInterval(TimeInterval(145 * 3_600 + 32 * 60 + 40))
        XCTAssertEqual(
            CountdownFormatter.text(to: target, now: now, placeholder: "-"),
            "145:32:40"
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
