import XCTest

@MainActor
final class WatchReadinessFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testWatchScoreAndAllThreeFactorShortcuts() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-ready", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let score = app.otherElements["readiness_score"]
        XCTAssertTrue(score.waitForExistence(timeout: 10))
        let demoNotice = app.staticTexts["demo_notice"]
        XCTAssertTrue(demoNotice.exists)
        XCTAssertLessThanOrEqual(demoNotice.frame.maxY, app.frame.maxY)
        capture("Watch 今日页", app: app)
        for (kind, title) in [("activity", "活动"), ("vitals", "生命体征"), ("sleep", "睡眠")] {
            let shortcut = app.buttons["factor_\(kind)"]
            XCTAssertTrue(shortcut.waitForExistence(timeout: 5))
            XCTAssertTrue(shortcut.isHittable, "\(title) should be reachable on the first screen")
            XCTAssertLessThanOrEqual(shortcut.frame.maxY, app.frame.maxY)
            shortcut.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            if kind == "sleep" {
                XCTAssertTrue(app.staticTexts["睡眠时长"].exists)
            }
            capture("Watch \(title)因素", app: app)
            app.navigationBars.buttons.firstMatch.tap()
        }
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
