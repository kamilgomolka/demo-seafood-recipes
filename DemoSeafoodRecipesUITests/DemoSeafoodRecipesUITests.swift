import XCTest

final class DemoSeafoodRecipesUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testListScrollsAndRefreshes() {
        let app = launch("success")
        XCTAssertTrue(app.staticTexts["Original seafood 1"].waitForExistence(timeout: 5))
        let list = app.collectionViews["seafood.list"]
        list.swipeUp()
        XCTAssertFalse(app.staticTexts["Original seafood 1"].isHittable)
        list.swipeDown()
        pullToRefresh(app)
        XCTAssertTrue(app.staticTexts["Updated seafood 1"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Original seafood 1"].exists)
    }

    @MainActor
    func testRecipeDetailOpensFromList() {
        let app = launch("success")
        XCTAssertTrue(app.descendants(matching: .any)["seafood.1"].firstMatch.waitForExistence(timeout: 5))
        app.descendants(matching: .any)["seafood.1"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Simmer the seafood until cooked through."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["• Salmon"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLocalSearchFiltersList() {
        let app = launch("success")
        XCTAssertTrue(app.staticTexts["Original seafood 1"].waitForExistence(timeout: 5))
        let field = app.searchFields["Search recipes"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("seafood 30")
        XCTAssertTrue(app.staticTexts["Original seafood 30"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Original seafood 1"].exists)
    }

    @MainActor
    func testFailureCanBeRetried() {
        let app = launch("failure")
        let retry = app.buttons["seafood.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        retry.tap()
        XCTAssertTrue(app.staticTexts["Updated seafood 1"].waitForExistence(timeout: 5))
        XCTAssertFalse(retry.exists)
    }

    @MainActor
    func testEmptyResultCanRefresh() {
        let app = launch("empty")
        XCTAssertTrue(app.staticTexts["No recipes"].waitForExistence(timeout: 5))
        pullToRefresh(app)
        XCTAssertTrue(app.staticTexts["Updated seafood 1"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testFailedRefreshPreservesContentAndCanRetry() {
        let app = launch("refreshFailure")
        XCTAssertTrue(app.staticTexts["Original seafood 1"].waitForExistence(timeout: 5))
        pullToRefresh(app)
        let retry = app.buttons["seafood.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Original seafood 1"].exists)
        app.buttons["scenario.recover"].tap()
        retry.tap()
        XCTAssertTrue(app.staticTexts["Updated seafood 1"].waitForExistence(timeout: 5))
        XCTAssertFalse(retry.exists)
    }

    @MainActor
    func testLifecycleCancellationAndRapidReentry() {
        let app = launch("lifecycle")
        assertStatus(app, requests: 1, cancellations: 0, revision: 0)
        app.buttons["scenario.visibility"].tap()
        assertStatus(app, requests: 1, cancellations: 1, revision: 0)
        app.buttons["scenario.visibility"].tap()
        app.buttons["scenario.complete"].tap()
        assertStatus(app, requests: 2, cancellations: 1, revision: 0)
        XCTAssertFalse(app.staticTexts["Original seafood 1"].exists)
        app.buttons["scenario.complete"].tap()
        XCTAssertTrue(app.staticTexts["Updated seafood 1"].waitForExistence(timeout: 5))

        app.buttons["scenario.updateParent"].tap()
        assertStatus(app, requests: 2, cancellations: 1, revision: 1)
        app.buttons["scenario.visibility"].tap()
        app.buttons["scenario.visibility"].tap()
        XCTAssertTrue(app.staticTexts["Updated seafood 1"].waitForExistence(timeout: 5))
        assertStatus(app, requests: 2, cancellations: 1, revision: 1)
    }

    @MainActor
    func testRefreshCancellationOnDisappear() {
        let app = launch("refreshLifecycle")
        assertStatus(app, requests: 1, cancellations: 0, revision: 0)
        XCTAssertTrue(app.staticTexts["Original seafood 1"].waitForExistence(timeout: 5))
        pullToRefresh(app)
        assertStatus(app, requests: 2, cancellations: 1, revision: 0)
        app.buttons["scenario.visibility"].tap()
        XCTAssertTrue(app.staticTexts["Original seafood 1"].waitForExistence(timeout: 5))
        pullToRefresh(app)
        assertStatus(app, requests: 3, cancellations: 1, revision: 0)
        XCTAssertTrue(app.staticTexts["Updated seafood 1"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--seafood-scenario", scenario]
        app.launch()
        return app
    }

    @MainActor
    private func pullToRefresh(_ app: XCUIApplication) {
        let list = app.collectionViews["seafood.list"]
        let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        start.press(forDuration: 0.1, thenDragTo: end)
    }

    @MainActor
    private func assertStatus(_ app: XCUIApplication, requests: Int, cancellations: Int, revision: Int) {
        let status = app.staticTexts["scenario.status"]
        let expected = "Requests: \(requests), cancellations: \(cancellations), revision: \(revision)"
        XCTAssertTrue(status.wait(for: \.label, toEqual: expected, timeout: 5))
    }
}
