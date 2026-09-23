import XCTest

@MainActor
final class WatchReadinessFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testWatchScoreAndSleepExplanation() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-ready", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let score = app.otherElements["readiness_score"]
        XCTAssertTrue(score.waitForExistence(timeout: 10))
        capture("Watch 今日页", app: app)
        let sleep = app.descendants(matching: .any).matching(identifier: "factor_sleep").firstMatch
        let scroll = app.scrollViews.firstMatch
        // Short drags avoid flicking past an entire row on the 42mm display.
        for _ in 0..<10 {
            let distance = sleep.frame.midY - scroll.frame.height * 0.66
            if abs(distance) < 18 { break }
            let movement = min(55, max(-55, distance))
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.76))
            let end = start.withOffset(CGVector(dx: 0, dy: -movement))
            start.press(forDuration: 0.1, thenDragTo: end,
                        withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        XCTAssertTrue(sleep.exists)
        XCTAssertGreaterThan(sleep.frame.midY, 85)
        XCTAssertLessThan(sleep.frame.midY, 205)
        capture("Watch 因素入口", app: app)
        sleep.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["睡眠"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["睡眠时长"].exists)
        capture("Watch 睡眠因素", app: app)
    }

    func testWatchMissingDataIsNotZeroScore() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-missing"]
        app.launch()
        XCTAssertTrue(app.staticTexts["暂无法评估"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.otherElements["readiness_score"].exists)
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
