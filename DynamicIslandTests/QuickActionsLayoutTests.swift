import XCTest
@testable import Notchly

final class QuickActionsLayoutTests: XCTestCase {
    func testNormalizedOrderDropsDuplicatesAndAppendsMissingActions() {
        let stored: [QuickAction] = [.screenshot, .timer, .screenshot]
        let result = QuickActionsLayout.normalizedOrder(stored)
        XCTAssertEqual(Array(result.prefix(2)), [.screenshot, .timer])
        XCTAssertEqual(Set(result), Set(QuickAction.allCases))
        XCTAssertEqual(result.count, QuickAction.allCases.count)
    }

    func testEmptyStoredOrderFallsBackToTheDefault() {
        XCTAssertEqual(QuickActionsLayout.normalizedOrder([]), QuickAction.defaultOrder)
    }

    func testHiddenActionsAreFilteredOutInOrder() {
        let visible = QuickActionsLayout.visibleActions(
            order: QuickAction.defaultOrder,
            hidden: [.stopwatch, .darkMode],
            shortcutName: "Focus"
        )
        XCTAssertFalse(visible.contains(.stopwatch))
        XCTAssertFalse(visible.contains(.darkMode))
        XCTAssertEqual(visible.first, .timer)
    }

    func testShortcutButtonNeedsANameToAppear() {
        let without = QuickActionsLayout.visibleActions(order: QuickAction.defaultOrder, hidden: [], shortcutName: "  ")
        XCTAssertFalse(without.contains(.shortcut))
        let with = QuickActionsLayout.visibleActions(order: QuickAction.defaultOrder, hidden: [], shortcutName: "Toggle Focus")
        XCTAssertTrue(with.contains(.shortcut))
    }

    func testMovingClampsAtTheEnds() {
        let order = QuickAction.defaultOrder
        XCTAssertEqual(QuickActionsLayout.moved(order, action: .timer, by: -1), order)
        XCTAssertEqual(QuickActionsLayout.moved(order, action: order.last!, by: 1), order)
    }

    func testMovingSwapsWithTheNeighbour() {
        let moved = QuickActionsLayout.moved(QuickAction.defaultOrder, action: .stopwatch, by: -1)
        XCTAssertEqual(Array(moved.prefix(2)), [.stopwatch, .timer])
        let movedDown = QuickActionsLayout.moved(QuickAction.defaultOrder, action: .timer, by: 1)
        XCTAssertEqual(Array(movedDown.prefix(2)), [.stopwatch, .timer])
    }

    func testEveryActionHasTitleAndSymbol() {
        for action in QuickAction.allCases {
            XCTAssertFalse(action.title.isEmpty)
            XCTAssertFalse(action.symbolName.isEmpty)
            XCTAssertFalse(action.activeSymbolName.isEmpty)
        }
    }
}
