import XCTest

@MainActor
final class ReadinessFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch(_ state: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-\(state)", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        return app
    }

    func testScoreAndAllThreeFactorDetails() {
        let app = launch("ready")
        XCTAssertTrue(app.otherElements["readiness_score"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["demo_notice"].exists)
        capture("iPhone 今日页", app: app)
        for kind in ["sleep", "vitals", "activity"] {
            let row = app.buttons["factor_\(kind)"]
            for _ in 0..<4 where !row.isHittable { app.swipeUp() }
            XCTAssertTrue(row.isHittable)
            row.tap()
            XCTAssertTrue(app.staticTexts["demo_notice"].waitForExistence(timeout: 3))
            XCTAssertTrue(app.navigationBars.buttons.firstMatch.isHittable)
            app.navigationBars.buttons.firstMatch.tap()
        }
    }

    func testBaselineAndMissingDataNeverShowNumericScore() {
        for state in ["baseline", "missing"] {
            let app = launch(state)
            let title = state == "baseline" ? "正在了解你的节奏" : "暂无法评估"
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 10))
            XCTAssertFalse(app.otherElements["readiness_score"].exists)
            capture("iPhone \(state)", app: app)
            app.terminate()
        }
    }

    func testOnboardingRequiresAgeConfirmation() {
        let app = launch("onboarding")
        let button = app.buttons["connect_health"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        XCTAssertFalse(button.isEnabled)
        let age = app.switches["confirm_age"]
        for _ in 0..<4 where !age.isHittable { app.swipeUp() }
        XCTAssertEqual(age.value as? String, "0")
        age.tap()
        let confirmed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: age)
        XCTAssertEqual(XCTWaiter.wait(for: [confirmed], timeout: 5), .completed)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
        capture("iPhone 连接健康数据", app: app)
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
