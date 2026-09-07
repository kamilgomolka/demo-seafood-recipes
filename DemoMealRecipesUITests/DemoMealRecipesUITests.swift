import XCTest

final class DemoMealRecipesUITests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testLaunchingSampleFeature() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["main.launchSampleFeatureButton"].tap()

        XCTAssertTrue(app.staticTexts["sampleFeature.bodyLabel"].waitForExistence(timeout: 5.0))
    }
}
