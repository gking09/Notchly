import XCTest
@testable import Notchly

final class BatteryExtrasTests: XCTestCase {

    // MARK: Fixtures (shapes taken from a real Apple Silicon MacBook)

    private func powerSource(
        level: Int = 80,
        plugged: Bool = true,
        charging: Bool = false,
        charged: Bool = false,
        toFull: Int? = 0,
        toEmpty: Int? = 0
    ) -> [String: Any] {
        var dict: [String: Any] = [
            "Current Capacity": level,
            "Max Capacity": 100,
            "Is Charging": charging,
            "Is Charged": charged,
            "Power Source State": plugged ? "AC Power" : "Battery Power",
            "DesignCycleCount": 1000
        ]
        if let toFull { dict["Time to Full Charge"] = toFull }
        if let toEmpty { dict["Time to Empty"] = toEmpty }
        return dict
    }

    private func smart(
        notChargingReason: Int? = nil,
        slowReason: Int = 0,
        amperage: Int? = nil,
        voltage: Int = 12_400,
        cycles: Int = 56,
        design: Int = 8579,
        nominal: Int? = 8624
    ) -> [String: Any] {
        var charger: [String: Any] = ["SlowChargingReason": slowReason]
        if let notChargingReason { charger["NotChargingReason"] = notChargingReason }
        var dict: [String: Any] = [
            "ChargerData": charger,
            "CycleCount": cycles,
            "DesignCapacity": design,
            "MaxCapacity": 100,
            "AppleRawMaxCapacity": 8380,
            "Voltage": voltage,
            "AvgTimeToFull": 1242
        ]
        if let nominal { dict["NominalChargeCapacity"] = nominal }
        if let amperage { dict["Amperage"] = NSNumber(value: amperage) }
        return dict
    }

    private let adapter: [String: Any] = ["Watts": 94, "Name": "96W USB-C Power Adapter"]

    // MARK: Time formatting

    func testTimeFormatting() {
        XCTAssertEqual(BatteryTimeFormatter.format(minutes: 72), "1h 12m")
        XCTAssertEqual(BatteryTimeFormatter.format(minutes: 45), "45m")
        XCTAssertEqual(BatteryTimeFormatter.format(minutes: 120), "2h")
        XCTAssertEqual(BatteryTimeFormatter.format(minutes: 60), "1h")
        XCTAssertEqual(BatteryTimeFormatter.format(minutes: 0), "<1m")
        XCTAssertEqual(BatteryTimeFormatter.format(minutes: -5), "<1m")
        XCTAssertEqual(BatteryTimeFormatter.format(minutes: 1), "1m")
    }

    func testEstimateTreatsNonPositiveAndSentinelsAsCalculating() {
        XCTAssertEqual(BatteryDetailsInterpreter.estimate(fromMinutes: -1), .calculating)
        XCTAssertEqual(BatteryDetailsInterpreter.estimate(fromMinutes: 0), .calculating)
        XCTAssertEqual(BatteryDetailsInterpreter.estimate(fromMinutes: 65535), .calculating)
        XCTAssertEqual(BatteryDetailsInterpreter.estimate(fromMinutes: 90), .minutes(90))
    }

    func testTimeInfoTexts() {
        let info = BatteryTimeInfo(kind: .toFull, estimate: .minutes(72))
        XCTAssertEqual(info.compactText, "1h 12m")
        XCTAssertEqual(info.minutes, 72)
        XCTAssertFalse(info.isCalculating)
        let calc = BatteryTimeInfo(kind: .remaining, estimate: .calculating)
        XCTAssertEqual(calc.compactText, "…")
        XCTAssertTrue(calc.isCalculating)
        XCTAssertNil(calc.minutes)
    }

    // MARK: Interpreting IOKit values

    func testChargingShowsTimeToFull() {
        let d = BatteryDetailsInterpreter.interpret(
            powerSource: powerSource(level: 50, charging: true, toFull: 72),
            smartBattery: smart(amperage: 2000),
            adapter: adapter
        )
        XCTAssertEqual(d.time, BatteryTimeInfo(kind: .toFull, estimate: .minutes(72)))
        XCTAssertEqual(d.adapterWatts, 94)
        XCTAssertTrue(d.isCharging)
    }

    func testChargingWithNegativeEstimateIsCalculating() {
        let d = BatteryDetailsInterpreter.interpret(
            powerSource: powerSource(level: 50, charging: true, toFull: -1),
            smartBattery: smart(),
            adapter: adapter
        )
        XCTAssertEqual(d.time?.estimate, .calculating)
        XCTAssertEqual(d.time?.kind, .toFull)
    }

    func testStaleAvgTimeToFullIsIgnoredWhenNotCharging() {
        // The real machine reports AvgTimeToFull = 1242 while holding at 80%.
        let d = BatteryDetailsInterpreter.interpret(
            powerSource: powerSource(charging: false, toFull: 0),
            smartBattery: smart(notChargingReason: 16_777_216),
            adapter: adapter
        )
        XCTAssertNil(d.time)
    }

    func testOnBatteryShowsTimeRemaining() {
        let d = BatteryDetailsInterpreter.interpret(
            powerSource: powerSource(level: 40, plugged: false, toEmpty: 185),
            smartBattery: smart(),
            adapter: nil
        )
        XCTAssertEqual(d.time, BatteryTimeInfo(kind: .remaining, estimate: .minutes(185)))
        XCTAssertNil(d.adapterWatts)
        XCTAssertEqual(d.state, .onBattery)
    }

    func testOnBatteryFallsBackToOSEstimateThenCalculating() {
        var ps = powerSource(level: 40, plugged: false)
        ps.removeValue(forKey: "Time to Empty")
        let fromEstimate = BatteryDetailsInterpreter.interpret(
            powerSource: ps, smartBattery: [:], adapter: nil, estimateSeconds: 3_600
        )
        XCTAssertEqual(fromEstimate.time?.estimate, .minutes(60))

        let unknown = BatteryDetailsInterpreter.interpret(
            powerSource: ps, smartBattery: [:], adapter: nil, estimateSeconds: -1
        )
        XCTAssertEqual(unknown.time?.estimate, .calculating)

        let nothing = BatteryDetailsInterpreter.interpret(
            powerSource: ps, smartBattery: [:], adapter: nil, estimateSeconds: nil
        )
        XCTAssertNil(nothing.time)
    }

    func testPluggedFullHasNoTime() {
        let d = BatteryDetailsInterpreter.interpret(
            powerSource: powerSource(level: 100, charging: false, charged: true),
            smartBattery: smart(),
            adapter: adapter
        )
        XCTAssertEqual(d.state, .full)
        XCTAssertNil(d.time)
    }

    func testHeldAtLimitComesFromNotChargingReason() {
        let d = BatteryDetailsInterpreter.interpret(
            powerSource: powerSource(level: 80, charging: false),
            smartBattery: smart(notChargingReason: 16_777_216),
            adapter: adapter
        )
        XCTAssertEqual(d.state, .held(atPercent: 80))
    }

    func testNotChargingWithoutReasonIsNeverCalledHeld() {
        let noKey = BatteryDetailsInterpreter.interpret(
            powerSource: powerSource(level: 80, charging: false),
            smartBattery: smart(notChargingReason: nil),
            adapter: adapter
        )
        XCTAssertEqual(noKey.state, .pluggedNotCharging)

        let zero = BatteryDetailsInterpreter.interpret(
            powerSource: powerSource(level: 80, charging: false),
            smartBattery: smart(notChargingReason: 0),
            adapter: adapter
        )
        XCTAssertEqual(zero.state, .pluggedNotCharging)

        let empty = BatteryDetailsInterpreter.interpret(
            powerSource: powerSource(level: 80, charging: false),
            smartBattery: [:],
            adapter: nil
        )
        XCTAssertEqual(empty.state, .pluggedNotCharging)
    }

    func testFastChargingNeedsMeasuredPower() {
        // 4000 mA x 12.4 V = 49.6 W
        let fast = BatteryDetailsInterpreter.interpret(
            powerSource: powerSource(level: 30, charging: true, toFull: 50),
            smartBattery: smart(amperage: 4000),
            adapter: adapter
        )
        XCTAssertEqual(fast.state, .fastCharging)
        XCTAssertEqual(fast.chargingPowerWatts ?? 0, 49.6, accuracy: 0.01)

        // 1000 mA x 12.4 V = 12.4 W
        let normal = BatteryDetailsInterpreter.interpret(
            powerSource: powerSource(level: 30, charging: true, toFull: 50),
            smartBattery: smart(amperage: 1000),
            adapter: adapter
        )
        XCTAssertEqual(normal.state, .charging)

        // No current reading at all: plain charging, never "fast".
        let unknown = BatteryDetailsInterpreter.interpret(
            powerSource: powerSource(level: 30, charging: true, toFull: 50),
            smartBattery: smart(amperage: nil),
            adapter: adapter
        )
        XCTAssertEqual(unknown.state, .charging)
        XCTAssertNil(unknown.chargingPowerWatts)
    }

    func testDischargingAmperageStoredUnsignedIsNotChargePower() {
        // -1500 mA as unsigned 64-bit, as AppleSmartBattery stores it.
        let wrapped = NSNumber(value: UInt64(bitPattern: Int64(-1500)))
        var sm = smart()
        sm["Amperage"] = wrapped
        let d = BatteryDetailsInterpreter.interpret(
            powerSource: powerSource(level: 30, charging: true, toFull: 50),
            smartBattery: sm,
            adapter: adapter
        )
        XCTAssertNil(d.chargingPowerWatts)
        XCTAssertEqual(d.state, .charging)
    }

    func testSlowChargingReasonWins() {
        let d = BatteryDetailsInterpreter.interpret(
            powerSource: powerSource(level: 30, charging: true, toFull: 200),
            smartBattery: smart(slowReason: 2, amperage: 4000),
            adapter: adapter
        )
        XCTAssertEqual(d.state, .slowCharging)
    }

    func testAdapterWattsOnlyWhilePlugged() {
        let unplugged = BatteryDetailsInterpreter.interpret(
            powerSource: powerSource(level: 40, plugged: false, toEmpty: 100),
            smartBattery: smart(),
            adapter: adapter
        )
        XCTAssertNil(unplugged.adapterWatts)

        // Falls back to AppleSmartBattery's own AdapterDetails.
        var sm = smart()
        sm["AdapterDetails"] = ["Watts": 67]
        let fallback = BatteryDetailsInterpreter.interpret(
            powerSource: powerSource(), smartBattery: sm, adapter: nil
        )
        XCTAssertEqual(fallback.adapterWatts, 67)
    }

    func testHealthAndCycles() {
        // Nominal capacity above design clamps to 100.
        let d = BatteryDetailsInterpreter.interpret(powerSource: powerSource(), smartBattery: smart(), adapter: adapter)
        XCTAssertEqual(d.healthPercent, 100)
        XCTAssertEqual(d.cycleCount, 56)
        XCTAssertEqual(d.designCycleCount, 1000)

        XCTAssertEqual(BatteryDetailsInterpreter.healthPercent(smartBattery: smart(nominal: 7200)), 84)
    }

    func testHealthFallsBackToRawThenIntelMaxCapacity() {
        XCTAssertEqual(BatteryDetailsInterpreter.healthPercent(smartBattery: smart(nominal: nil)), 98)

        // Intel: MaxCapacity is mAh and there is no raw key.
        let intel: [String: Any] = ["DesignCapacity": 6000, "MaxCapacity": 5400]
        XCTAssertEqual(BatteryDetailsInterpreter.healthPercent(smartBattery: intel), 90)

        // Apple Silicon MaxCapacity == 100 is a percentage, not mAh.
        let percentOnly: [String: Any] = ["DesignCapacity": 8579, "MaxCapacity": 100]
        XCTAssertNil(BatteryDetailsInterpreter.healthPercent(smartBattery: percentOnly))

        XCTAssertNil(BatteryDetailsInterpreter.healthPercent(smartBattery: [:]))
    }

    func testEmptySmartBatteryLeavesOptionalDataNil() {
        let d = BatteryDetailsInterpreter.interpret(
            powerSource: powerSource(level: 55, plugged: false, toEmpty: 100),
            smartBattery: [:],
            adapter: nil
        )
        XCTAssertNil(d.healthPercent)
        XCTAssertNil(d.cycleCount)
        XCTAssertNil(d.adapterWatts)
        XCTAssertEqual(d.level, 55)
    }

    // MARK: Alert state machine

    private let config = BatteryAlertConfig()

    private func reading(_ level: Int, plugged: Bool = false, held: Bool = false) -> BatteryAlertReading {
        BatteryAlertReading(level: level, isPluggedIn: plugged, isHeld: held)
    }

    func testLowFiresOnceWhenCrossingAndNotOnFirstReading() {
        var machine = BatteryAlertStateMachine()
        XCTAssertNil(machine.update(reading(25), config: config))
        XCTAssertNil(machine.update(reading(21), config: config))
        XCTAssertEqual(machine.update(reading(20), config: config), .low)
        XCTAssertNil(machine.update(reading(19), config: config))
        XCTAssertNil(machine.update(reading(15), config: config))
    }

    func testLaunchingAlreadyLowDoesNotAlertButStaysArmedForCritical() {
        var machine = BatteryAlertStateMachine()
        XCTAssertNil(machine.update(reading(15), config: config))
        XCTAssertNil(machine.update(reading(14), config: config))
        XCTAssertEqual(machine.update(reading(10), config: config), .critical)
        XCTAssertNil(machine.update(reading(9), config: config))
    }

    func testCriticalOutranksLowWhenLevelJumpsPastBoth() {
        var machine = BatteryAlertStateMachine()
        _ = machine.update(reading(30), config: config)
        XCTAssertEqual(machine.update(reading(8), config: config), .critical)
        // The low alert was consumed by the same drop.
        XCTAssertNil(machine.update(reading(7), config: config))
    }

    func testLowThenCriticalAreSeparateAlerts() {
        var machine = BatteryAlertStateMachine()
        _ = machine.update(reading(22), config: config)
        XCTAssertEqual(machine.update(reading(20), config: config), .low)
        XCTAssertEqual(machine.update(reading(10), config: config), .critical)
    }

    func testDisabledCriticalFallsThroughToLow() {
        var cfg = config
        cfg.criticalEnabled = false
        var machine = BatteryAlertStateMachine()
        _ = machine.update(reading(30), config: cfg)
        XCTAssertEqual(machine.update(reading(8), config: cfg), .low)
    }

    func testDisabledLowIsSilentButCriticalStillFires() {
        var cfg = config
        cfg.lowEnabled = false
        var machine = BatteryAlertStateMachine()
        _ = machine.update(reading(30), config: cfg)
        XCTAssertNil(machine.update(reading(18), config: cfg))
        XCTAssertEqual(machine.update(reading(9), config: cfg), .critical)
    }

    func testLowRearmsOnlyAfterHysteresisClearance() {
        var machine = BatteryAlertStateMachine()
        _ = machine.update(reading(25), config: config)
        XCTAssertEqual(machine.update(reading(20), config: config), .low)
        // Bobbing just above the threshold does not re-arm it.
        XCTAssertNil(machine.update(reading(22), config: config))
        XCTAssertNil(machine.update(reading(20), config: config))
        // Charging well above the threshold does.
        _ = machine.update(reading(30, plugged: true), config: config)
        _ = machine.update(reading(30), config: config)
        XCTAssertEqual(machine.update(reading(20), config: config), .low)
    }

    func testNoLowAlertsWhilePluggedIn() {
        var machine = BatteryAlertStateMachine()
        _ = machine.update(reading(50, plugged: true), config: config)
        XCTAssertNil(machine.update(reading(5, plugged: true), config: config))
    }

    func testFullFiresOnTheWayUpOnly() {
        var machine = BatteryAlertStateMachine()
        XCTAssertNil(machine.update(reading(97, plugged: true), config: config))
        XCTAssertNil(machine.update(reading(99, plugged: true), config: config))
        XCTAssertEqual(machine.update(reading(100, plugged: true), config: config), .full)
        XCTAssertNil(machine.update(reading(100, plugged: true), config: config))
    }

    func testPluggingInAtFullDoesNotAlert() {
        var machine = BatteryAlertStateMachine()
        XCTAssertNil(machine.update(reading(100, plugged: true), config: config))
        XCTAssertNil(machine.update(reading(100, plugged: true), config: config))
    }

    func testFullUsesConfiguredChargeLimit() {
        var cfg = config
        cfg.fullThreshold = 80
        var machine = BatteryAlertStateMachine()
        _ = machine.update(reading(78, plugged: true), config: cfg)
        XCTAssertEqual(machine.update(reading(80, plugged: true), config: cfg), .full)
    }

    func testUnpluggingDisarmsFullAlert() {
        var machine = BatteryAlertStateMachine()
        _ = machine.update(reading(90, plugged: true), config: config)
        _ = machine.update(reading(92), config: config)
        XCTAssertNil(machine.update(reading(100, plugged: true), config: config))
    }

    func testChargeHeldFiresOncePerHold() {
        var machine = BatteryAlertStateMachine()
        _ = machine.update(reading(78, plugged: true), config: config)
        XCTAssertEqual(machine.update(reading(80, plugged: true, held: true), config: config), .chargeHeld)
        XCTAssertNil(machine.update(reading(80, plugged: true, held: true), config: config))
        // Full is still armed and fires later if charging resumes to 100.
        _ = machine.update(reading(85, plugged: true), config: config)
        XCTAssertEqual(machine.update(reading(100, plugged: true), config: config), .full)
    }

    func testAlreadyHeldAtLaunchIsSilentAndCanBeDisabled() {
        var machine = BatteryAlertStateMachine()
        XCTAssertNil(machine.update(reading(80, plugged: true, held: true), config: config))
        XCTAssertNil(machine.update(reading(80, plugged: true, held: true), config: config))

        var cfg = config
        cfg.chargeHeldEnabled = false
        var other = BatteryAlertStateMachine()
        _ = other.update(reading(70, plugged: true), config: cfg)
        XCTAssertNil(other.update(reading(80, plugged: true, held: true), config: cfg))
    }

    func testHeldAtTheFullThresholdReportsFullNotBoth() {
        var cfg = config
        cfg.fullThreshold = 80
        var machine = BatteryAlertStateMachine()
        _ = machine.update(reading(75, plugged: true), config: cfg)
        XCTAssertEqual(machine.update(reading(80, plugged: true, held: true), config: cfg), .full)
        XCTAssertNil(machine.update(reading(80, plugged: true, held: true), config: cfg))
    }

    // MARK: Bluetooth low battery tracker

    private func device(_ id: String, _ level: Int) -> BluetoothBatteryReading {
        BluetoothBatteryReading(id: id, name: id, level: level, symbol: nil)
    }

    func testBluetoothAlertsOncePerSession() {
        var tracker = BluetoothLowBatteryTracker()
        let connected: Set<String> = ["a", "b"]
        var fresh = tracker.update(connectedIDs: connected, readings: [device("a", 18), device("b", 80)], threshold: 20, enabled: true)
        XCTAssertEqual(fresh.map(\.id), ["a"])
        fresh = tracker.update(connectedIDs: connected, readings: [device("a", 17), device("b", 80)], threshold: 20, enabled: true)
        XCTAssertTrue(fresh.isEmpty)
        fresh = tracker.update(connectedIDs: connected, readings: [device("a", 12), device("b", 15)], threshold: 20, enabled: true)
        XCTAssertEqual(fresh.map(\.id), ["b"])
    }

    func testBluetoothSessionResetsOnDisconnect() {
        var tracker = BluetoothLowBatteryTracker()
        _ = tracker.update(connectedIDs: ["a"], readings: [device("a", 10)], threshold: 20, enabled: true)
        // Disconnects...
        _ = tracker.update(connectedIDs: [], readings: [], threshold: 20, enabled: true)
        // ...and reconnects still low: a new session, a new alert.
        let fresh = tracker.update(connectedIDs: ["a"], readings: [device("a", 10)], threshold: 20, enabled: true)
        XCTAssertEqual(fresh.map(\.id), ["a"])
    }

    func testBluetoothDisabledDoesNotConsumeTheAlert() {
        var tracker = BluetoothLowBatteryTracker()
        var fresh = tracker.update(connectedIDs: ["a"], readings: [device("a", 10)], threshold: 20, enabled: false)
        XCTAssertTrue(fresh.isEmpty)
        fresh = tracker.update(connectedIDs: ["a"], readings: [device("a", 10)], threshold: 20, enabled: true)
        XCTAssertEqual(fresh.map(\.id), ["a"])
    }

    func testBluetoothThresholdBoundaryAndUnknownLevels() {
        var tracker = BluetoothLowBatteryTracker()
        let fresh = tracker.update(
            connectedIDs: ["at", "over", "zero", "gone"],
            readings: [device("at", 20), device("over", 21), device("zero", 0), device("gone", 5)],
            threshold: 20,
            enabled: true
        )
        // "gone" has a reading but is not in the connected set this round.
        XCTAssertEqual(Set(fresh.map(\.id)), ["at", "gone"])

        var strict = BluetoothLowBatteryTracker()
        let none = strict.update(connectedIDs: ["x"], readings: [device("y", 5)], threshold: 20, enabled: true)
        XCTAssertTrue(none.isEmpty)
    }
}
