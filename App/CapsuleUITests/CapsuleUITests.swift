//
//  CapsuleUITests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Golden UI tests for the critical flows. These run through Xcode/xcodebuild against the
//  built .app (not SwiftPM `swift test`). The app is launched in a deterministic MockBackend
//  mode via CAPSULE_UITEST=1 (see CapsuleScene.init), so no real `container` CLI is required
//  and the seeded data is stable. CI runs them in the `app-ui-tests` job.

import XCTest

final class CapsuleUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Launches the app in deterministic UI-test mode. `scenario` picks the seeded backend
    /// state: nil/"healthy" (default) or "serviceDown".
    @MainActor
    private func launchApp(scenario: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CAPSULE_UITEST"] = "1"
        if let scenario { app.launchEnvironment["CAPSULE_UITEST_SCENARIO"] = scenario }
        app.launch()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 20),
            "App did not reach the foreground after launch")
        return app
    }

    /// First element anywhere in the app matching an accessibility identifier.
    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// First element anywhere whose accessibility label equals `label` (for tab items etc.).
    private func labeled(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", label))
            .firstMatch
    }

    // MARK: - Launch & shell

    @MainActor
    func testAppLaunchesToForeground() {
        let app = launchApp()
        XCTAssertEqual(app.state, .runningForeground)
    }

    @MainActor
    func testSidebarShowsCoreSections() {
        let app = launchApp()
        XCTAssertTrue(
            element("sidebar-containers", in: app).waitForExistence(timeout: 15),
            "sidebar should list Containers")
        XCTAssertTrue(element("sidebar-images", in: app).exists, "sidebar should list Images")
        XCTAssertTrue(element("sidebar-system", in: app).exists, "sidebar should list System")
    }

    @MainActor
    func testContainersSurfaceShowsSeededData() {
        let app = launchApp()
        let containers = element("sidebar-containers", in: app)
        if containers.waitForExistence(timeout: 15) { containers.click() }
        // MockBackend seeds a container named "web".
        XCTAssertTrue(
            app.staticTexts["web"].waitForExistence(timeout: 15),
            "the seeded 'web' container should appear in the list")
    }

    // MARK: - Sheets (critical flows)

    @MainActor
    func testBuildSheetOpensViaShortcut() {
        let app = launchApp()
        // ⇧⌘B → "Build from Folder…" (always enabled; no selection needed).
        app.typeKey("b", modifierFlags: [.shift, .command])
        XCTAssertTrue(
            element("build-sheet", in: app).waitForExistence(timeout: 15),
            "the Build sheet should open")
        app.typeKey(.escape, modifierFlags: [])
    }

    @MainActor
    func testRunSheetOpensFromImageSelection() {
        let app = launchApp()
        element("sidebar-images", in: app).click()
        let alpine = app.staticTexts["docker.io/library/alpine:latest"]
        XCTAssertTrue(
            alpine.waitForExistence(timeout: 15), "the seeded alpine image should appear")
        alpine.click()
        // ⇧⌘R → "Run Selected Image…" (enabled once an image is selected).
        app.typeKey("r", modifierFlags: [.shift, .command])
        XCTAssertTrue(
            element("run-sheet", in: app).waitForExistence(timeout: 15),
            "the Run sheet should open for the selected image")
        app.typeKey(.escape, modifierFlags: [])
    }

    @MainActor
    func testCommandPaletteOpensViaShortcut() {
        let app = launchApp()
        app.typeKey("k", modifierFlags: .command)  // ⌘K
        XCTAssertTrue(
            element("command-palette", in: app).waitForExistence(timeout: 15),
            "the command palette should open")
        app.typeKey(.escape, modifierFlags: [])
    }

    @MainActor
    func testPullSheetBrowseFlowComposesReference() {
        let app = launchApp()
        // ⇧⌘P → "Pull Image…". The sheet must open in Reference mode (the default).
        app.typeKey("p", modifierFlags: [.shift, .command])
        let referenceField = app.textFields.firstMatch
        XCTAssertTrue(
            referenceField.waitForExistence(timeout: 15),
            "the Pull sheet should open showing the Reference form by default")

        // Flip to Browse and search the seeded catalog (MockImageRegistry.sample).
        let browseSegment = labeled("Browse", in: app)
        XCTAssertTrue(
            browseSegment.waitForExistence(timeout: 10),
            "the Pull sheet should offer a Browse segment")
        browseSegment.click()
        let searchField = element("pull-browse-search-field", in: app)
        XCTAssertTrue(
            searchField.waitForExistence(timeout: 10), "the browse search field should focus")
        searchField.typeText("nginx")

        // Results appear after the debounce; pick the official nginx repository.
        let nginxRow = app.staticTexts["nginx"]
        XCTAssertTrue(
            nginxRow.waitForExistence(timeout: 15),
            "searching the seeded catalog should list the official nginx repository")
        nginxRow.click()

        // Pick the seeded "latest" tag; the sheet must return to the Reference form
        // with the fully-qualified reference composed for the existing pull path.
        let latestTag = app.staticTexts["latest"]
        XCTAssertTrue(
            latestTag.waitForExistence(timeout: 15),
            "selecting a repository should list its seeded tags")
        latestTag.click()
        XCTAssertTrue(
            referenceField.waitForExistence(timeout: 10),
            "picking a tag should land back in the Reference form")
        XCTAssertEqual(
            referenceField.value as? String, "docker.io/library/nginx:latest",
            "the composed reference should fill the existing Reference field")
        app.typeKey(.escape, modifierFlags: [])
    }

    // MARK: - Settings

    @MainActor
    func testSettingsShowsUpdatesAndPrivacyTabs() {
        let app = launchApp()
        app.typeKey(",", modifierFlags: .command)  // ⌘, → Settings

        // The Updates tab item, then its page.
        let updatesTab = labeled("Updates", in: app)
        XCTAssertTrue(
            updatesTab.waitForExistence(timeout: 15), "Settings should have an Updates tab")
        updatesTab.click()
        XCTAssertTrue(
            element("updates-settings-page", in: app).waitForExistence(timeout: 10),
            "the Updates settings page should render")
        XCTAssertTrue(
            element("updates-check-button", in: app).exists,
            "the Updates page should offer a Check for Updates button")

        // The Privacy tab, then its page.
        let privacyTab = labeled("Privacy", in: app)
        XCTAssertTrue(
            privacyTab.waitForExistence(timeout: 10), "Settings should have a Privacy tab")
        privacyTab.click()
        XCTAssertTrue(
            element("privacy-page", in: app).waitForExistence(timeout: 10),
            "the Privacy page should render")
    }

    // MARK: - Error state

    @MainActor
    func testServiceDownShowsErrorBanner() {
        let app = launchApp(scenario: "serviceDown")
        let banner = element("system-health-banner", in: app)
        XCTAssertTrue(
            banner.waitForExistence(timeout: 15), "the system-health banner should be present")
        XCTAssertTrue(
            banner.label.localizedCaseInsensitiveContains("stopped"),
            "with the service down the banner should say services are stopped; got: \(banner.label)"
        )
    }
}
