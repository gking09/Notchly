import XCTest
@testable import Notchly

/// The closed-notch live activities put content in two wings either side of the
/// hardware cut-out. These pin the arithmetic that keeps the cut-out empty.
final class NotchWingLayoutTests: XCTestCase {
    /// A 14" MacBook Pro's notch, as the app measures it (auxiliary areas + 4).
    private let notch: CGFloat = 185

    func testGapIsExactlyTheNotchWhateverTheContent() {
        for (left, right) in [(0, 0), (20, 20), (44, 180), (180, 44), (400, 10), (1, 999)] as [(CGFloat, CGFloat)] {
            let layout = NotchWingLayout.make(notchWidth: notch, leftContent: left, rightContent: right)
            XCTAssertEqual(layout.centerGap, notch, "left \(left) right \(right)")
        }
    }

    func testWingsAreAlwaysSymmetricSoTheGapStaysCentred() {
        // The AirPods listening-mode HUD: a 44pt icon on the left, a 180pt label on the right.
        let layout = NotchWingLayout.make(notchWidth: notch, leftContent: 44, rightContent: 180)
        XCTAssertEqual(layout.leftWing, layout.rightWing)
        XCTAssertEqual(layout.leftWing, 180)
        // The content's midpoint is the gap's midpoint, i.e. the notch's.
        XCTAssertEqual(layout.leftWing + layout.centerGap / 2, layout.totalWidth / 2)
    }

    func testWiderLeftContentSizesBothWings() {
        let layout = NotchWingLayout.make(notchWidth: notch, leftContent: 140, rightContent: 20)
        XCTAssertEqual(layout.leftWing, 140)
        XCTAssertEqual(layout.rightWing, 140)
        XCTAssertEqual(layout.totalWidth, 140 + notch + 140)
    }

    func testMinimumWingIsAFloor() {
        let layout = NotchWingLayout.make(notchWidth: notch, leftContent: 10, rightContent: 12, minimumWing: 26)
        XCTAssertEqual(layout.leftWing, 26)
        XCTAssertEqual(layout.rightWing, 26)
    }

    func testInnerClearanceIsIncludedInTheWingAndLeftOutOfTheContentWidth() {
        let layout = NotchWingLayout.make(notchWidth: notch, leftContent: 90, rightContent: 60, innerClearance: 4)
        XCTAssertEqual(layout.leftWing, 94)
        XCTAssertEqual(layout.contentWidth, 90)
        XCTAssertEqual(layout.centerGap, notch)
    }

    func testHoverFlapWidensTheGapOnly() {
        let layout = NotchWingLayout.make(notchWidth: notch, leftContent: 30, rightContent: 30, centerExtra: 8)
        XCTAssertEqual(layout.notchWidth, notch)
        XCTAssertEqual(layout.centerGap, notch + 8)
        XCTAssertEqual(layout.leftWing, 30)
    }

    func testWingsShrinkToFitTheScreenButTheGapDoesNot() {
        let layout = NotchWingLayout.make(
            notchWidth: notch,
            leftContent: 300,
            rightContent: 300,
            maximumTotalWidth: 500
        )
        // (500 - 185) / 2 = 157.5 each
        XCTAssertEqual(layout.leftWing, 157.5)
        XCTAssertEqual(layout.rightWing, 157.5)
        XCTAssertEqual(layout.totalWidth, 500)
        XCTAssertEqual(layout.centerGap, notch)
        XCTAssertTrue(layout.isConstrained)
    }

    func testRoomyScreenLeavesWingsAtTheirContent() {
        let layout = NotchWingLayout.make(
            notchWidth: notch,
            leftContent: 60,
            rightContent: 80,
            maximumTotalWidth: 1600
        )
        XCTAssertEqual(layout.leftWing, 80)
        XCTAssertFalse(layout.isConstrained)
    }

    func testNoRoomAtAllCollapsesTheWingsNotTheGap() {
        let layout = NotchWingLayout.make(
            notchWidth: notch,
            leftContent: 100,
            rightContent: 100,
            innerClearance: 4,
            maximumTotalWidth: 100
        )
        XCTAssertEqual(layout.leftWing, 0)
        XCTAssertEqual(layout.rightWing, 0)
        XCTAssertEqual(layout.centerGap, notch)
        XCTAssertEqual(layout.contentWidth, 0)
    }

    func testDisplayWithoutANotchUsesTheFakeNotchWidthAsTheGap() {
        // The app's default fake notch on a notchless display.
        let fake: CGFloat = 150
        let layout = NotchWingLayout.make(notchWidth: fake, leftContent: 92, rightContent: 92, innerClearance: 4)
        XCTAssertEqual(layout.centerGap, fake)
        XCTAssertEqual(layout.leftWing, layout.rightWing)
        XCTAssertEqual(layout.totalWidth, fake + 2 * 96)
    }

    func testNonsenseInputsAreTreatedAsZero() {
        let layout = NotchWingLayout.make(
            notchWidth: -5,
            leftContent: .nan,
            rightContent: -20,
            minimumWing: .infinity,
            centerExtra: .nan
        )
        XCTAssertEqual(layout.centerGap, 0)
        XCTAssertEqual(layout.leftWing, 0)
        XCTAssertEqual(layout.rightWing, 0)
    }

    // MARK: Available width

    private let screen = CGRect(x: 0, y: 0, width: 1710, height: 1107)

    func testAvailableWidthWithoutMenusIsTheScreenLessMarginsAndPadding() {
        let width = NotchWingLayout.availableContentWidth(
            screenFrame: screen,
            menusRightEdge: nil,
            menuGap: 8,
            shapePadding: 14,
            screenMargin: 16
        )
        XCTAssertEqual(width, 1710 - 2 * (16 + 14))
    }

    func testShortMenusDoNotConstrainTheWings() {
        let width = NotchWingLayout.availableContentWidth(
            screenFrame: screen,
            menusRightEdge: 606,
            menuGap: 8,
            shapePadding: 14
        )
        // Menus end at 606; the content may reach back to 606 + 8 + 14 = 628,
        // which is 227 from the centre, i.e. 454 wide -- far narrower than the
        // screen, but still more than any activity asks for, so the limit is 454.
        XCTAssertEqual(width, 454)
    }

    func testMenusReachingTheNotchLeaveNoRoomForWings() {
        let width = NotchWingLayout.availableContentWidth(
            screenFrame: screen,
            menusRightEdge: 900,
            menuGap: 8,
            shapePadding: 14
        )
        XCTAssertEqual(width, 0)
    }

    func testMenuLimitKeepsTheWingsSymmetricAndTheGapOnTheNotch() {
        let available = NotchWingLayout.availableContentWidth(
            screenFrame: screen,
            menusRightEdge: 700,
            menuGap: 8,
            shapePadding: 14
        )
        let layout = NotchWingLayout.make(
            notchWidth: notch,
            leftContent: 300,
            rightContent: 40,
            maximumTotalWidth: available
        )
        // Left edge of the content stays clear of the menus...
        let leftEdge = screen.midX - layout.totalWidth / 2 - 14
        XCTAssertGreaterThanOrEqual(leftEdge, 700 + 8 - 0.001)
        // ...and the gap is still the notch, centred.
        XCTAssertEqual(layout.centerGap, notch)
        XCTAssertEqual(layout.leftWing, layout.rightWing)
    }

    func testTextWidthOfEmptyStringIsZeroAndGrowsWithLength() {
        let font = NSFont.systemFont(ofSize: 12)
        XCTAssertEqual(NotchWingLayout.textWidth("", font: font), 0)
        XCTAssertGreaterThan(
            NotchWingLayout.textWidth("A longer title", font: font),
            NotchWingLayout.textWidth("Short", font: font)
        )
    }
}

final class HUDMotionTests: XCTestCase {
    func testEdgesAreDetectedAtEitherEnd() {
        XCTAssertEqual(HUDMotion.edge(for: 0), .minimum)
        XCTAssertEqual(HUDMotion.edge(for: 1), .maximum)
        XCTAssertEqual(HUDMotion.edge(for: 0.0004), .minimum)
        XCTAssertEqual(HUDMotion.edge(for: 0.9996), .maximum)
        XCTAssertNil(HUDMotion.edge(for: 0.5))
        XCTAssertNil(HUDMotion.edge(for: 0.01))
        XCTAssertNil(HUDMotion.edge(for: .nan))
    }

    func testVolumeSymbolSlashesWhenMutedAndFillsWithLevelOtherwise() {
        let muted = HUDMotion.volumeSymbol(level: 0)
        XCTAssertEqual(muted.name, "speaker.slash.fill")
        XCTAssertNil(muted.variableValue)

        let half = HUDMotion.volumeSymbol(level: 0.5)
        XCTAssertEqual(half.name, "speaker.wave.3.fill")
        XCTAssertEqual(half.variableValue ?? -1, 0.5, accuracy: 0.0001)
    }

    func testVolumeSymbolClampsOutOfRangeLevels() {
        XCTAssertEqual(HUDMotion.volumeSymbol(level: 7).variableValue ?? -1, 1, accuracy: 0.0001)
        XCTAssertEqual(HUDMotion.volumeSymbol(level: -3).name, "speaker.slash.fill")
    }

    func testBrightnessAndBacklightSwapAtTheMidpoint() {
        XCTAssertEqual(HUDMotion.brightnessSymbol(level: 0.49), "sun.min.fill")
        XCTAssertEqual(HUDMotion.brightnessSymbol(level: 0.5), "sun.max.fill")
        XCTAssertEqual(HUDMotion.backlightSymbol(level: 0.2), "light.min")
        XCTAssertEqual(HUDMotion.backlightSymbol(level: 0.9), "light.max")
    }

    func testGlyphScaleSwellsWithTheLevel() {
        XCTAssertEqual(HUDMotion.glyphScale(level: 0), 0.88, accuracy: 0.0001)
        XCTAssertEqual(HUDMotion.glyphScale(level: 1), 1.04, accuracy: 0.0001)
        XCTAssertLessThan(HUDMotion.glyphScale(level: 0.2), HUDMotion.glyphScale(level: 0.8))
    }

    func testPercentageRoundsAndClamps() {
        XCTAssertEqual(HUDMotion.percentage(0.504), 50)
        XCTAssertEqual(HUDMotion.percentage(0.506), 51)
        XCTAssertEqual(HUDMotion.percentage(2), 100)
        XCTAssertEqual(HUDMotion.percentage(-1), 0)
        XCTAssertEqual(HUDMotion.percentage(.nan), 0)
    }
}

final class MusicWingMetricsTests: XCTestCase {
    func testWithoutTrackInfoWingsAskForJustTheArtworkAndVisualizer() {
        XCTAssertEqual(MusicWingMetrics.leftContent(artworkWidth: 20, titleWidth: 90, showsTrackInfo: false), 20)
        XCTAssertEqual(MusicWingMetrics.rightContent(visualizerWidth: 16, artistWidth: 70, showsTrackInfo: false), 16)
    }

    func testTrackInfoAddsTheTextAndASpacer() {
        XCTAssertEqual(MusicWingMetrics.leftContent(artworkWidth: 20, titleWidth: 80, showsTrackInfo: true), 106)
        XCTAssertEqual(MusicWingMetrics.rightContent(visualizerWidth: 16, artistWidth: 60, showsTrackInfo: true), 82)
    }

    func testLongTextIsCappedSoItMarqueesInsteadOfWideningTheNotch() {
        XCTAssertEqual(
            MusicWingMetrics.leftContent(artworkWidth: 20, titleWidth: 900, showsTrackInfo: true),
            MusicWingMetrics.maxTrackInfoWidth
        )
        XCTAssertEqual(
            MusicWingMetrics.rightContent(visualizerWidth: 16, artistWidth: 900, showsTrackInfo: true),
            MusicWingMetrics.maxTrackInfoWidth
        )
    }

    func testTextFieldWidthNeverGoesNegative() {
        XCTAssertEqual(MusicWingMetrics.textFieldWidth(wingContentWidth: 100, reserved: 20), 74)
        XCTAssertEqual(MusicWingMetrics.textFieldWidth(wingContentWidth: 10, reserved: 40), 0)
    }

    func testTrackInfoWingsAgreeWithTheLayoutThatSizesThem() {
        let layout = NotchWingLayout.make(
            notchWidth: 185,
            leftContent: MusicWingMetrics.leftContent(artworkWidth: 23, titleWidth: 500, showsTrackInfo: true),
            rightContent: MusicWingMetrics.rightContent(visualizerWidth: 16, artistWidth: 40, showsTrackInfo: true),
            innerClearance: NotchWingLayout.innerClearance
        )
        XCTAssertEqual(layout.leftWing, layout.rightWing)
        XCTAssertEqual(layout.centerGap, 185)
        XCTAssertEqual(layout.leftWing, MusicWingMetrics.maxTrackInfoWidth + NotchWingLayout.innerClearance)
    }
}
