import AppKit
import AVFoundation
import CoreBluetooth
import Defaults
import SwiftUI
import XCTest
@testable import Notchly

@MainActor
final class OnboardingTests: XCTestCase {

    // MARK: Steps

    func testThreeStepsInOrder() {
        XCTAssertEqual(OnboardingStep.allCases, [.welcome, .permissions, .done])
        XCTAssertEqual(OnboardingStep.count, 3)
        XCTAssertEqual(OnboardingStep.welcome.number, 1)
        XCTAssertEqual(OnboardingStep.done.number, 3)
    }

    func testNavigationStopsAtTheEnds() {
        XCTAssertNil(OnboardingStep.welcome.previous)
        XCTAssertEqual(OnboardingStep.welcome.next, .permissions)
        XCTAssertEqual(OnboardingStep.permissions.next, .done)
        XCTAssertEqual(OnboardingStep.permissions.previous, .welcome)
        XCTAssertNil(OnboardingStep.done.next)
        XCTAssertTrue(OnboardingStep.welcome.isFirst)
        XCTAssertTrue(OnboardingStep.done.isLast)
        XCTAssertFalse(OnboardingStep.permissions.isFirst || OnboardingStep.permissions.isLast)
    }

    func testStepTitlesAreDistinct() {
        let titles = OnboardingStep.allCases.map(\.title)
        XCTAssertEqual(Set(titles).count, titles.count)
        XCTAssertFalse(titles.contains(""))
    }

    // MARK: Permission list

    func testListOnlyHasPermissionsTheAppUses() {
        XCTAssertEqual(
            Set(OnboardingPermission.allCases),
            [.accessibility, .automation, .camera, .bluetooth, .fullDiskAccess]
        )
        // These two are never asked for, so they must not be offered.
        let titles = OnboardingPermission.allCases.map { $0.title.lowercased() }
        XCTAssertFalse(titles.contains { $0.contains("screen recording") })
        XCTAssertFalse(titles.contains { $0.contains("microphone") })
    }

    func testEveryPermissionHasCopySymbolAndSettingsPane() {
        for permission in OnboardingPermission.allCases {
            XCTAssertFalse(permission.title.isEmpty)
            XCTAssertFalse(permission.detail.isEmpty)
            XCTAssertNotNil(NSImage(systemSymbolName: permission.symbol, accessibilityDescription: nil), permission.symbol)
            XCTAssertEqual(permission.settingsURL.scheme, "x-apple.systempreferences")
            XCTAssertTrue(permission.settingsURL.absoluteString.contains("Privacy_"))
            XCTAssertFalse((permission.title + permission.detail).contains("Atoll"))
        }
        XCTAssertEqual(Set(OnboardingPermission.allCases.map(\.symbol)).count, OnboardingPermission.allCases.count)
    }

    func testAutomationCannotBeRequestedUpFront() {
        XCTAssertFalse(OnboardingPermission.automation.canRequest)
        XCTAssertEqual(OnboardingPermission.automation.initialStatus, .onDemand)
        XCTAssertNil(OnboardingPermission.automation.actionTitle(for: .onDemand))
        for permission in OnboardingPermission.allCases where permission != .automation {
            XCTAssertTrue(permission.canRequest)
            XCTAssertEqual(permission.initialStatus, .notGranted)
        }
    }

    func testActionTitleFollowsStatus() {
        XCTAssertEqual(OnboardingPermission.camera.actionTitle(for: .notGranted), "Grant")
        XCTAssertEqual(OnboardingPermission.camera.actionTitle(for: .denied), "Open Settings")
        XCTAssertNil(OnboardingPermission.camera.actionTitle(for: .granted))
    }

    func testStatusMapping() {
        XCTAssertEqual(OnboardingPermissionStatus(accessibilityTrusted: true), .granted)
        XCTAssertEqual(OnboardingPermissionStatus(accessibilityTrusted: false), .notGranted)
        XCTAssertEqual(OnboardingPermissionStatus(camera: .authorized), .granted)
        XCTAssertEqual(OnboardingPermissionStatus(camera: .notDetermined), .notGranted)
        XCTAssertEqual(OnboardingPermissionStatus(camera: .denied), .denied)
        XCTAssertEqual(OnboardingPermissionStatus(camera: .restricted), .denied)
        XCTAssertEqual(OnboardingPermissionStatus(bluetooth: .allowedAlways), .granted)
        XCTAssertEqual(OnboardingPermissionStatus(bluetooth: .notDetermined), .notGranted)
        XCTAssertEqual(OnboardingPermissionStatus(bluetooth: .denied), .denied)
        XCTAssertTrue(OnboardingPermissionStatus.granted.isGranted)
        XCTAssertFalse(OnboardingPermissionStatus.denied.isGranted)
    }

    func testFrozenControllerReportsGivenStatuses() {
        let controller = OnboardingPermissionsController(
            statuses: [.accessibility: .granted, .camera: .denied],
            liveChecks: false
        )
        XCTAssertEqual(controller.status(for: .accessibility), .granted)
        XCTAssertEqual(controller.status(for: .camera), .denied)
        XCTAssertEqual(controller.status(for: .bluetooth), .notGranted)
        controller.refresh()
        XCTAssertEqual(controller.status(for: .accessibility), .granted, "a frozen controller must not re-read the system")
    }

    // MARK: Copy

    func testCopyMatchesTheBrief() {
        XCTAssertEqual(OnboardingCopy.tip, "Hover over the notch to open it. Drag files or text onto it to stash them.")
        XCTAssertEqual(OnboardingCopy.permissionsFooter, "You can do this later in Settings.")
        for text in [OnboardingCopy.tagline, OnboardingCopy.permissionsTitle, OnboardingCopy.permissionsSubtitle] {
            XCTAssertFalse(text.isEmpty)
            XCTAssertFalse(text.contains("Atoll") || text.contains("Pro"))
        }
    }

    // MARK: Defaults

    func testFirstLaunchDefaultsFollowTheHardware() {
        let saved = (Defaults[.menubarIcon], Defaults[.enableHaptics], Defaults[.enableLyrics], Defaults[.externalDisplayStyle])
        defer {
            (Defaults[.menubarIcon], Defaults[.enableHaptics], Defaults[.enableLyrics], Defaults[.externalDisplayStyle]) = saved
        }

        Defaults[.menubarIcon] = false
        Defaults[.enableHaptics] = false
        Defaults[.enableLyrics] = true
        OnboardingDefaults.applyFirstLaunchDefaults(hasNotch: true)
        XCTAssertTrue(Defaults[.menubarIcon])
        XCTAssertTrue(Defaults[.enableHaptics])
        XCTAssertFalse(Defaults[.enableLyrics])
        XCTAssertEqual(Defaults[.externalDisplayStyle], .notch)

        OnboardingDefaults.applyFirstLaunchDefaults(hasNotch: false)
        XCTAssertEqual(Defaults[.externalDisplayStyle], .dynamicIsland)
    }

    // MARK: Visual check (opt-in)

    /// Renders every onboarding step in light and dark. Skipped unless `NOTCHLY_RENDER_DIR`
    /// is set (pass it as `TEST_RUNNER_NOTCHLY_RENDER_DIR=/some/dir`).
    func testRenderOnboardingStepsToPNG() throws {
        guard let directory = ProcessInfo.processInfo.environment["NOTCHLY_RENDER_DIR"], !directory.isEmpty else {
            throw XCTSkip("NOTCHLY_RENDER_DIR not set")
        }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        let statuses: [OnboardingPermission: OnboardingPermissionStatus] = [
            .accessibility: .granted, .automation: .onDemand, .camera: .notGranted,
            .bluetooth: .denied, .fullDiskAccess: .notGranted,
        ]
        let size = OnboardingView.windowSize
        for step in OnboardingStep.allCases {
            for dark in [false, true] {
                let view = OnboardingView(
                    initialStep: step,
                    permissions: OnboardingPermissionsController(statuses: statuses, liveChecks: false),
                    applyFirstLaunchDefaults: false,
                    onFinish: {},
                    onOpenSettings: {}
                )
                let host = NSHostingView(rootView: view)
                host.frame = NSRect(origin: .zero, size: size)
                let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                window.contentView = host
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.8))
                host.layoutSubtreeIfNeeded()

                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
                host.cacheDisplay(in: host.bounds, to: rep)

                let image = NSImage(size: size)
                image.lockFocus()
                (dark ? NSColor(white: 0.14, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
                NSRect(origin: .zero, size: size).fill()
                rep.draw(in: NSRect(origin: .zero, size: size))
                image.unlockFocus()

                guard let tiff = image.tiffRepresentation,
                      let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { continue }
                try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("onboarding-\(step.number)-\(step)-\(dark ? "dark" : "light").png"))
            }
        }
    }
}
