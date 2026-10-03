import XCTest

@testable import Notchly

/// The gate decides how much background work is worth doing; the pollers just
/// ask it. These pin the policy so a refactor cannot quietly make the notch
/// busier on battery.
final class ActivityGateTests: XCTestCase {
    func testPluggedInIsNeverReduced() {
        let gate = ActivityGate(efficiencyModeEnabled: true, lowPowerMode: false, onBattery: false, screenAsleep: false)
        XCTAssertFalse(gate.reducedActivity)
        XCTAssertEqual(gate.interval(3), 3)
        XCTAssertEqual(gate.frameRate(30), 30)
    }

    func testBatteryReducesWhenEfficiencyIsOn() {
        let gate = ActivityGate(efficiencyModeEnabled: true, lowPowerMode: false, onBattery: true)
        XCTAssertTrue(gate.reducedActivity)
        XCTAssertEqual(gate.interval(3), 6)
        XCTAssertLessThan(gate.frameRate(30), 30)
        XCTAssertGreaterThanOrEqual(gate.frameRate(30), 12)
    }

    func testLowPowerModeReducesEvenOnAdapter() {
        let gate = ActivityGate(efficiencyModeEnabled: true, lowPowerMode: true, onBattery: false)
        XCTAssertTrue(gate.reducedActivity)
        XCTAssertEqual(gate.frameRate(30), 15)
    }

    func testTurningEfficiencyOffRestoresFullActivity() {
        let gate = ActivityGate(efficiencyModeEnabled: false, lowPowerMode: true, onBattery: true)
        XCTAssertFalse(gate.reducedActivity)
        XCTAssertEqual(gate.interval(3), 3)
        XCTAssertEqual(gate.frameRate(30), 30)
    }

    func testScreenSleepSuspendsRegardlessOfSetting() {
        XCTAssertTrue(ActivityGate(efficiencyModeEnabled: false, screenAsleep: true).isSuspended)
        XCTAssertFalse(ActivityGate(screenAsleep: false).isSuspended)
    }

    func testFrameRateNeverDropsBelowTheFloorOrAboveTheBase() {
        let gate = ActivityGate(efficiencyModeEnabled: true, lowPowerMode: true, onBattery: true)
        XCTAssertEqual(gate.frameRate(20, minimum: 10), 10)
        XCTAssertEqual(gate.frameRate(8, minimum: 12), 8, "a base below the floor is left alone")
        XCTAssertEqual(gate.frameInterval(30), 1.0 / 15.0, accuracy: 0.0001)
    }

    func testToleranceScalesWithIntervalAndHonoursMinimum() {
        XCTAssertEqual(ActivityGate.tolerance(for: 60, minimum: 5), 12, accuracy: 0.0001)
        XCTAssertEqual(ActivityGate.tolerance(for: 3, fraction: 0.25, minimum: 0.5), 0.75, accuracy: 0.0001)
        XCTAssertEqual(ActivityGate.tolerance(for: 1, fraction: 0.1, minimum: 0.5), 0.5, accuracy: 0.0001)
        XCTAssertEqual(ActivityGate.tolerance(for: 10, fraction: 5), 5, accuracy: 0.0001, "capped at half the interval")
    }

    func testHubClockTicksPerMinuteOnlyWhenSecondsHiddenAndReduced() {
        XCTAssertEqual(HubClockFormatter.tickInterval(showSeconds: true, reducedActivity: true), 1)
        XCTAssertEqual(HubClockFormatter.tickInterval(showSeconds: true, reducedActivity: false), 1)
        XCTAssertEqual(HubClockFormatter.tickInterval(showSeconds: false, reducedActivity: false), 1)
        XCTAssertEqual(HubClockFormatter.tickInterval(showSeconds: false, reducedActivity: true), 60)
    }
}
