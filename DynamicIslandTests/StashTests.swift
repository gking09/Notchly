import XCTest
@testable import Notchly

// MARK: - Policy

final class StashPolicyTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 2_000_000)

    func testRetentionLifetimes() {
        XCTAssertEqual(StashRetention.oneHour.lifetime, 3_600)
        XCTAssertEqual(StashRetention.day.lifetime, 86_400)
        XCTAssertEqual(StashRetention.week.lifetime, 604_800)
        XCTAssertNil(StashRetention.untilQuit.lifetime)
        XCTAssertNil(StashRetention.untilCleared.lifetime)
    }

    func testExpiryHappensExactlyAtTheLifetime() {
        XCTAssertFalse(StashRetention.oneHour.isExpired(createdAt: t0, now: t0.addingTimeInterval(3_599)))
        XCTAssertTrue(StashRetention.oneHour.isExpired(createdAt: t0, now: t0.addingTimeInterval(3_600)))
    }

    func testOpenEndedRetentionsNeverExpireByTime() {
        let far = t0.addingTimeInterval(86_400 * 3_650)
        XCTAssertFalse(StashRetention.untilCleared.isExpired(createdAt: t0, now: far))
        XCTAssertFalse(StashRetention.untilQuit.isExpired(createdAt: t0, now: far))
        XCTAssertNil(StashRetention.untilCleared.expiryDate(createdAt: t0))
        XCTAssertEqual(StashRetention.day.expiryDate(createdAt: t0), t0.addingTimeInterval(86_400))
    }

    func testOnlyUntilQuitClearsOnLaunch() {
        for retention in StashRetention.allCases {
            XCTAssertEqual(retention.clearsOnLaunch, retention == .untilQuit)
        }
    }

    func testSizePolicyLinksOnlyStrictlyAboveTheThreshold() {
        let policy = StashSizePolicy(linkThresholdBytes: 1_000)
        XCTAssertEqual(policy.decision(forByteSize: 0), .copy)
        XCTAssertEqual(policy.decision(forByteSize: 1_000), .copy)
        XCTAssertEqual(policy.decision(forByteSize: 1_001), .link)
    }

    func testDefaultThresholdIs200Megabytes() {
        let policy = StashSizePolicy(megabytes: StashSizePolicy.defaultThresholdMegabytes)
        XCTAssertEqual(policy.linkThresholdBytes, 200_000_000)
        XCTAssertEqual(policy.decision(forByteSize: 199_999_999), .copy)
        XCTAssertEqual(policy.decision(forByteSize: 200_000_001), .link)
    }

    func testNegativeThresholdIsClampedToZero() {
        XCTAssertEqual(StashSizePolicy(linkThresholdBytes: -5).linkThresholdBytes, 0)
        XCTAssertEqual(StashSizePolicy(megabytes: -1).linkThresholdBytes, 0)
    }

    func testMaxItemsIsClampedIntoRange() {
        XCTAssertEqual(StashLimits.clampedMaxItems(0), StashLimits.maxItemsRange.lowerBound)
        XCTAssertEqual(StashLimits.clampedMaxItems(10_000), StashLimits.maxItemsRange.upperBound)
        XCTAssertEqual(StashLimits.clampedMaxItems(50), 50)
    }
}

// MARK: - Text helpers

final class StashTextTests: XCTestCase {
    func testFirstLineSkipsBlankLines() {
        XCTAssertEqual(StashText.firstLine(of: "\n\n  hello \nworld"), "hello")
    }

    func testPreviewKeepsTheFirstLinesAndMarksTruncation() {
        let text = "one\ntwo\nthree\nfour\nfive"
        XCTAssertEqual(StashText.preview(of: text, lineLimit: 3, characterLimit: 100), "one\ntwo\nthree\u{2026}")
        XCTAssertEqual(StashText.preview(of: "short", lineLimit: 3, characterLimit: 100), "short")
    }

    func testPreviewCapsCharacters() {
        let preview = StashText.preview(of: String(repeating: "a", count: 500), lineLimit: 4, characterLimit: 20)
        XCTAssertEqual(preview, String(repeating: "a", count: 20) + "\u{2026}")
    }

    func testPreviewWithNoRoomIsEmpty() {
        XCTAssertEqual(StashText.preview(of: "abc", lineLimit: 0, characterLimit: 10), "")
    }
}

// MARK: - Store

@MainActor
final class StashStoreTests: XCTestCase {
    private final class Clock {
        var now = Date(timeIntervalSince1970: 3_000_000)
        func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    }

    private var root: URL!
    private var stash: URL!
    private var sources: URL!
    private var clock: Clock!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("StashTests-\(UUID().uuidString)")
        stash = root.appendingPathComponent("Stash")
        sources = root.appendingPathComponent("Sources")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        clock = Clock()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeStore(
        retention: StashRetention = .day,
        maxItems: Int = 50,
        thresholdBytes: Int64 = 200_000_000
    ) -> StashStore {
        let clock = self.clock!
        return StashStore(
            directory: stash,
            configuration: StashConfiguration(
                retention: retention,
                maxItems: maxItems,
                sizePolicy: StashSizePolicy(linkThresholdBytes: thresholdBytes)
            ),
            now: { clock.now }
        )
    }

    @discardableResult
    private func makeSource(_ name: String, bytes: Int = 10) throws -> URL {
        let url = sources.appendingPathComponent(name)
        try Data(repeating: 0x61, count: bytes).write(to: url)
        return url
    }

    private func exists(_ item: StashItem, in store: StashStore) -> Bool {
        guard let url = store.fileURL(for: item) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private func added(_ result: StashAddResult, file: StaticString = #filePath, line: UInt = #line) -> StashItem {
        guard case .added(let item) = result else {
            XCTFail("Expected .added, got \(result)", file: file, line: line)
            return StashItem(kind: .text, createdAt: .distantPast)
        }
        return item
    }

    // MARK: Adding

    func testAddingTextStoresItInline() {
        let store = makeStore()
        let item = added(store.add(.text("hello world")))
        XCTAssertEqual(item.kind, .text)
        XCTAssertEqual(item.text, "hello world")
        XCTAssertNil(item.file)
        XCTAssertEqual(store.items, [item])
    }

    func testBlankTextIsRefused() {
        let store = makeStore()
        XCTAssertEqual(store.add(.text("  \n\t ")), .failed(.empty))
        XCTAssertTrue(store.items.isEmpty)
    }

    func testOversizedTextIsRefused() {
        let store = makeStore()
        let huge = String(repeating: "x", count: StashLimits.maximumTextBytes + 1)
        XCTAssertEqual(store.add(.text(huge)), .failed(.textTooLarge))
        XCTAssertTrue(store.items.isEmpty)
    }

    func testAddingALinkKeepsItsAbsoluteString() throws {
        let store = makeStore()
        let item = added(store.add(.url(try XCTUnwrap(URL(string: "https://example.com/a?b=1")))))
        XCTAssertEqual(item.kind, .url)
        XCTAssertEqual(item.text, "https://example.com/a?b=1")
        XCTAssertEqual(item.webURL?.host, "example.com")
    }

    func testItemsAreNewestFirst() {
        let store = makeStore()
        store.add(.text("first"))
        clock.advance(1)
        store.add(.text("second"))
        clock.advance(1)
        store.add(.text("third"))
        XCTAssertEqual(store.items.map(\.text), ["third", "second", "first"])
    }

    func testAddingTheSameTextAgainMovesItToTheFront() {
        let store = makeStore()
        store.add(.text("a"))
        clock.advance(1)
        store.add(.text("b"))
        clock.advance(1)
        let result = store.add(.text("a"))
        guard case .refreshed(let item) = result else { return XCTFail("Expected .refreshed") }
        XCTAssertEqual(item.text, "a")
        XCTAssertEqual(store.items.map(\.text), ["a", "b"])
        XCTAssertEqual(store.items.count, 2)
    }

    // MARK: Files

    func testSmallFileIsCopiedAndSurvivesTheOriginalBeingDeleted() throws {
        let store = makeStore()
        let source = try makeSource("notes.txt", bytes: 42)
        let item = added(store.add(.file(source)))

        XCTAssertEqual(item.kind, .file)
        XCTAssertEqual(item.file?.displayName, "notes.txt")
        XCTAssertEqual(item.file?.byteSize, 42)
        XCTAssertEqual(item.isLinked, false)
        XCTAssertNotNil(item.file?.storedPath)
        XCTAssertTrue(exists(item, in: store))
        // Stored under the stash directory, keeping the original name.
        let copy = try XCTUnwrap(store.fileURL(for: item))
        XCTAssertTrue(copy.path.hasPrefix(stash.path))
        XCTAssertEqual(copy.lastPathComponent, "notes.txt")

        try FileManager.default.removeItem(at: source)
        XCTAssertTrue(exists(item, in: store))
        XCTAssertEqual(try Data(contentsOf: copy).count, 42)
    }

    func testFileOverTheThresholdIsLinkedNotCopied() throws {
        let store = makeStore(thresholdBytes: 100)
        let source = try makeSource("big.bin", bytes: 101)
        let item = added(store.add(.file(source)))

        XCTAssertTrue(item.isLinked)
        XCTAssertNil(item.file?.storedPath)
        XCTAssertEqual(item.file?.originalPath, source.path)
        XCTAssertNotNil(item.file?.bookmark)
        XCTAssertEqual(store.fileURL(for: item)?.standardizedFileURL.path, source.standardizedFileURL.path)
        // Nothing was copied.
        let files = stash.appendingPathComponent(StashFileStager.filesFolder)
        XCTAssertFalse(FileManager.default.fileExists(atPath: files.path)
                       && !((try? FileManager.default.contentsOfDirectory(atPath: files.path)) ?? []).isEmpty)
    }

    func testFileExactlyAtTheThresholdIsStillCopied() throws {
        let store = makeStore(thresholdBytes: 100)
        let item = added(store.add(.file(try makeSource("edge.bin", bytes: 100))))
        XCTAssertFalse(item.isLinked)
    }

    func testRemovingALinkedItemNeverTouchesTheOriginal() throws {
        let store = makeStore(thresholdBytes: 1)
        let source = try makeSource("keep.bin", bytes: 50)
        let item = added(store.add(.file(source)))
        XCTAssertTrue(item.isLinked)
        store.remove(id: item.id)
        store.commitPendingRemoval()
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testFolderIsCopiedWithItsContents() throws {
        let store = makeStore()
        let folder = sources.appendingPathComponent("Project")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 20).write(to: folder.appendingPathComponent("a.txt"))
        let item = added(store.add(.file(folder)))
        XCTAssertEqual(item.file?.isDirectory, true)
        XCTAssertEqual(item.file?.byteSize, 20)
        let copy = try XCTUnwrap(store.fileURL(for: item))
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.appendingPathComponent("a.txt").path))
    }

    func testLargeFolderIsLinkedByTheSizeOfItsContents() throws {
        let store = makeStore(thresholdBytes: 30)
        let folder = sources.appendingPathComponent("Big")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 20).write(to: folder.appendingPathComponent("a"))
        try Data(repeating: 1, count: 20).write(to: folder.appendingPathComponent("b"))
        let item = added(store.add(.file(folder)))
        XCTAssertTrue(item.isLinked)
    }

    func testMissingFileFailsAsUnreadable() {
        let store = makeStore()
        XCTAssertEqual(store.add(.file(sources.appendingPathComponent("nope.txt"))), .failed(.unreadable))
        XCTAssertTrue(store.items.isEmpty)
    }

    func testImageDataIsSavedAsAFile() throws {
        let store = makeStore()
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
        let item = added(store.add(.image(bytes, fileExtension: ".png")))
        XCTAssertEqual(item.kind, .image)
        XCTAssertTrue(item.showsThumbnail)
        XCTAssertEqual(item.file?.displayName.hasSuffix(".png"), true)
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(store.fileURL(for: item))), bytes)
    }

    func testScratchFileIsMovedIntoTheStash() throws {
        let store = makeStore(thresholdBytes: 1)
        let scratch = try makeSource("incoming.dat", bytes: 500)
        let item = added(store.add(.scratchFile(scratch)))
        // A scratch file is always ours to keep, however big.
        XCTAssertFalse(item.isLinked)
        XCTAssertFalse(FileManager.default.fileExists(atPath: scratch.path))
        XCTAssertTrue(exists(item, in: store))
    }

    func testImageFilesAreMarkedForThumbnails() throws {
        let store = makeStore()
        let photo = try makeSource("photo.png", bytes: 8)
        let doc = try makeSource("doc.txt", bytes: 8)
        XCTAssertTrue(added(store.add(.file(photo))).showsThumbnail)
        XCTAssertFalse(added(store.add(.file(doc))).showsThumbnail)
    }

    // MARK: Cap

    func testOldestItemsAreEvictedPastTheCap() {
        let store = makeStore(maxItems: 3)
        for index in 1...5 {
            clock.advance(1)
            store.add(.text("item \(index)"))
        }
        XCTAssertEqual(store.items.map(\.text), ["item 5", "item 4", "item 3"])
    }

    func testEvictionDeletesTheEvictedFiles() throws {
        let store = makeStore(maxItems: 1)
        let first = added(store.add(.file(try makeSource("one.txt"))))
        let firstURL = try XCTUnwrap(store.fileURL(for: first))
        clock.advance(1)
        let second = added(store.add(.file(try makeSource("two.txt"))))
        XCTAssertEqual(store.items, [second])
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstURL.path))
        XCTAssertTrue(exists(second, in: store))
    }

    func testLoweringTheCapEvictsImmediately() {
        let store = makeStore(maxItems: 10)
        for index in 1...6 {
            clock.advance(1)
            store.add(.text("n\(index)"))
        }
        store.configuration.maxItems = 2
        XCTAssertEqual(store.items.map(\.text), ["n6", "n5"])
    }

    // MARK: Removal and undo

    func testRemoveThenUndoRestoresTheItemInPlace() {
        let store = makeStore()
        store.add(.text("a"))
        clock.advance(1)
        let b = added(store.add(.text("b")))
        clock.advance(1)
        store.add(.text("c"))

        XCTAssertTrue(store.remove(id: b.id))
        XCTAssertEqual(store.items.map(\.text), ["c", "a"])
        XCTAssertEqual(store.pendingRemoval?.reason, .removed)

        XCTAssertEqual(store.undoRemoval(), 1)
        XCTAssertEqual(store.items.map(\.text), ["c", "b", "a"])
        XCTAssertNil(store.pendingRemoval)
    }

    func testRemovingAnUnknownItemDoesNothing() {
        let store = makeStore()
        XCTAssertFalse(store.remove(id: UUID()))
        XCTAssertNil(store.pendingRemoval)
    }

    func testFilesSurviveUntilTheUndoWindowIsCommitted() throws {
        let store = makeStore()
        let item = added(store.add(.file(try makeSource("a.txt"))))
        let url = try XCTUnwrap(store.fileURL(for: item))

        store.remove(id: item.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Undo needs the file to still exist")

        store.commitPendingRemoval()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertNil(store.pendingRemoval)
        XCTAssertEqual(store.undoRemoval(), 0, "Nothing is left to undo once committed")
    }

    func testClearThenUndoRestoresEverythingInOrder() throws {
        let store = makeStore()
        store.add(.text("a"))
        clock.advance(1)
        store.add(.text("b"))
        clock.advance(1)
        store.add(.file(try makeSource("c.txt")))
        let before = store.items

        XCTAssertEqual(store.clear(), 3)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertEqual(store.pendingRemoval?.reason, .cleared)

        XCTAssertEqual(store.undoRemoval(), 3)
        XCTAssertEqual(store.items, before)
        XCTAssertTrue(exists(store.items[0], in: store))
    }

    func testClearingAnEmptyStashDoesNothing() {
        let store = makeStore()
        XCTAssertEqual(store.clear(), 0)
        XCTAssertNil(store.pendingRemoval)
    }

    func testClearCommitDeletesAllCopiedFiles() throws {
        let store = makeStore()
        let item = added(store.add(.file(try makeSource("a.txt"))))
        let folder = try XCTUnwrap(store.fileURL(for: item)).deletingLastPathComponent()
        store.clear()
        store.commitPendingRemoval()
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    func testANewRemovalCommitsTheEarlierOne() throws {
        let store = makeStore()
        let a = added(store.add(.file(try makeSource("a.txt"))))
        clock.advance(1)
        let b = added(store.add(.text("b")))
        let aURL = try XCTUnwrap(store.fileURL(for: a))

        store.remove(id: a.id)
        store.remove(id: b.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: aURL.path))
        XCTAssertEqual(store.pendingRemoval?.items, [b])
        XCTAssertEqual(store.undoRemoval(), 1)
        XCTAssertEqual(store.items, [b])
    }

    func testAddingSomethingEndsTheUndoWindow() {
        let store = makeStore()
        let a = added(store.add(.text("a")))
        store.remove(id: a.id)
        clock.advance(1)
        store.add(.text("b"))
        XCTAssertNil(store.pendingRemoval)
        XCTAssertEqual(store.items.map(\.text), ["b"])
    }

    func testUndoRespectsTheCap() {
        let store = makeStore(maxItems: 2)
        store.add(.text("a"))
        clock.advance(1)
        store.add(.text("b"))
        store.clear()
        clock.advance(1)
        // A fresh add commits the clear, so rebuild the situation: remove one, add one, undo.
        store.add(.text("c"))
        clock.advance(1)
        store.add(.text("d"))
        let d = store.items[0]
        store.remove(id: d.id)
        XCTAssertEqual(store.undoRemoval(), 1)
        XCTAssertLessThanOrEqual(store.items.count, 2)
    }

    func testRemoveAllImmediatelyLeavesNothingToUndo() throws {
        let store = makeStore()
        let item = added(store.add(.file(try makeSource("a.txt"))))
        let url = try XCTUnwrap(store.fileURL(for: item))
        store.removeAllImmediately()
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertNil(store.pendingRemoval)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: Expiry

    func testExpiredItemsAreDroppedWithTheirFiles() throws {
        let store = makeStore(retention: .oneHour)
        let old = added(store.add(.file(try makeSource("old.txt"))))
        let oldURL = try XCTUnwrap(store.fileURL(for: old))
        clock.advance(1_800)
        store.add(.text("fresh"))

        clock.advance(1_800) // old is now 1h old, fresh is 30min old
        XCTAssertEqual(store.purgeExpired(), 1)
        XCTAssertEqual(store.items.map(\.text), ["fresh"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
    }

    func testNothingExpiresWhenRetentionIsUntilCleared() {
        let store = makeStore(retention: .untilCleared)
        store.add(.text("keep"))
        clock.advance(86_400 * 400)
        XCTAssertEqual(store.purgeExpired(), 0)
        XCTAssertEqual(store.items.count, 1)
    }

    func testChangingRetentionAppliesToExistingItems() {
        let store = makeStore(retention: .week)
        store.add(.text("a"))
        clock.advance(7_200)
        XCTAssertEqual(store.purgeExpired(), 0)
        store.configuration.retention = .oneHour
        XCTAssertEqual(store.purgeExpired(), 1)
    }

    // MARK: Persistence

    func testItemsSurviveARelaunchIncludingTextAndFiles() throws {
        let store = makeStore()
        store.add(.text("line one\nline two"))
        clock.advance(1)
        store.add(.url(try XCTUnwrap(URL(string: "https://example.com"))))
        clock.advance(1)
        let file = added(store.add(.file(try makeSource("doc.txt", bytes: 12))))
        let before = store.items

        let reopened = makeStore()
        reopened.load()
        XCTAssertEqual(reopened.items, before)
        let restored = try XCTUnwrap(reopened.items.first { $0.id == file.id })
        XCTAssertTrue(exists(restored, in: reopened))
        XCTAssertEqual(reopened.items.last?.text, "line one\nline two")
    }

    func testLinkedItemsRoundTripWithTheirBookmark() throws {
        let store = makeStore(thresholdBytes: 1)
        let source = try makeSource("big.bin", bytes: 40)
        let item = added(store.add(.file(source)))

        let reopened = makeStore(thresholdBytes: 1)
        reopened.load()
        let restored = try XCTUnwrap(reopened.items.first)
        XCTAssertEqual(restored, item)
        XCTAssertEqual(reopened.fileURL(for: restored)?.standardizedFileURL.path, source.standardizedFileURL.path)
    }

    func testLoadDropsItemsThatExpiredWhileTheAppWasClosed() throws {
        let store = makeStore(retention: .oneHour)
        let item = added(store.add(.file(try makeSource("a.txt"))))
        let url = try XCTUnwrap(store.fileURL(for: item))
        clock.advance(3_600)

        let reopened = makeStore(retention: .oneHour)
        reopened.load()
        XCTAssertTrue(reopened.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testUntilQuitClearsEverythingOnTheNextLaunch() throws {
        let store = makeStore(retention: .untilQuit)
        let item = added(store.add(.file(try makeSource("a.txt"))))
        let url = try XCTUnwrap(store.fileURL(for: item))
        store.add(.text("t"))

        let reopened = makeStore(retention: .untilQuit)
        reopened.load()
        XCTAssertTrue(reopened.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testLoadDropsCopiedItemsWhoseFileHasVanished() throws {
        let store = makeStore()
        let item = added(store.add(.file(try makeSource("a.txt"))))
        store.add(.text("still here"))
        try FileManager.default.removeItem(at: try XCTUnwrap(store.fileURL(for: item)))

        let reopened = makeStore()
        reopened.load()
        XCTAssertEqual(reopened.items.map(\.text), ["still here"])
    }

    func testLoadSweepsFilesNoItemOwns() throws {
        let store = makeStore()
        let item = added(store.add(.file(try makeSource("a.txt"))))
        store.remove(id: item.id) // pending: files on disk, not in the saved list
        let folder = try XCTUnwrap(store.fileURL(for: item)).deletingLastPathComponent()
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))

        let reopened = makeStore() // the app "quit" during the undo window
        reopened.load()
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    func testLoadSurvivesACorruptMetadataFile() throws {
        try FileManager.default.createDirectory(at: stash, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: stash.appendingPathComponent(StashStore.metadataFileName))
        let store = makeStore()
        store.load()
        XCTAssertTrue(store.items.isEmpty)
        // And it still works afterwards.
        store.add(.text("ok"))
        XCTAssertEqual(store.items.count, 1)
    }

    func testRemovalIsPersistedImmediately() {
        let store = makeStore()
        let item = added(store.add(.text("gone")))
        store.remove(id: item.id)
        let reopened = makeStore()
        reopened.load()
        XCTAssertTrue(reopened.items.isEmpty)
    }
}

// MARK: - Pasteboard reading

final class StashPasteboardReaderTests: XCTestCase {
    func testConcealedContentIsNeverTaken() {
        let snapshot = StashPasteboardSnapshot(
            types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"],
            string: "hunter2"
        )
        XCTAssertEqual(StashPasteboardReader.read(snapshot), .concealed)
    }

    func testTransientContentIsNeverTaken() {
        let snapshot = StashPasteboardSnapshot(
            types: ["public.utf8-plain-text", "org.nspasteboard.TransientType"],
            string: "one-time code 123456"
        )
        XCTAssertEqual(StashPasteboardReader.read(snapshot), .concealed)
    }

    func testPrivateMarkerWinsEvenWithFilesPresent() {
        let snapshot = StashPasteboardSnapshot(
            types: ["public.file-url", "org.nspasteboard.ConcealedType"],
            fileURLs: [URL(fileURLWithPath: "/tmp/a.txt")]
        )
        XCTAssertEqual(StashPasteboardReader.read(snapshot), .concealed)
    }

    func testPlainTextIsTaken() {
        let snapshot = StashPasteboardSnapshot(types: ["public.utf8-plain-text"], string: "just some text")
        XCTAssertEqual(StashPasteboardReader.read(snapshot), .payloads([.text("just some text")]))
    }

    func testFilesWinOverTheNameAndIconFinderAlsoPutsThere() {
        let url = URL(fileURLWithPath: "/tmp/report.pdf")
        let snapshot = StashPasteboardSnapshot(
            types: ["public.file-url", "public.utf8-plain-text", "public.tiff"],
            fileURLs: [url],
            string: "report.pdf",
            imageData: Data([1, 2, 3])
        )
        XCTAssertEqual(StashPasteboardReader.read(snapshot), .payloads([.file(url)]))
    }

    func testSeveralFilesAreAllTaken() {
        let urls = [URL(fileURLWithPath: "/tmp/a"), URL(fileURLWithPath: "/tmp/b")]
        let snapshot = StashPasteboardSnapshot(fileURLs: urls)
        XCTAssertEqual(StashPasteboardReader.read(snapshot), .payloads(urls.map { .file($0) }))
    }

    func testImageIsTakenWhenThereAreNoFiles() {
        let data = Data([9, 9, 9])
        let snapshot = StashPasteboardSnapshot(string: "alt text", imageData: data)
        XCTAssertEqual(StashPasteboardReader.read(snapshot), .payloads([.image(data, fileExtension: "png")]))
    }

    func testAStringThatIsOnlyALinkBecomesALinkItem() throws {
        let snapshot = StashPasteboardSnapshot(string: "  https://example.com/path?q=1\n")
        XCTAssertEqual(
            StashPasteboardReader.read(snapshot),
            .payloads([.url(try XCTUnwrap(URL(string: "https://example.com/path?q=1")))])
        )
    }

    func testSentencesContainingALinkStayText() {
        XCTAssertEqual(
            StashPasteboardReader.payload(forText: "see https://example.com for details"),
            .text("see https://example.com for details")
        )
    }

    func testOddSchemesAndHostlessLinksStayText() {
        XCTAssertEqual(StashPasteboardReader.payload(forText: "javascript:alert(1)"), .text("javascript:alert(1)"))
        XCTAssertEqual(StashPasteboardReader.payload(forText: "https://"), .text("https://"))
        XCTAssertEqual(StashPasteboardReader.payload(forText: "note: remember"), .text("note: remember"))
    }

    func testEmptyAndWhitespaceOnlyPasteboardsAreEmpty() {
        XCTAssertEqual(StashPasteboardReader.read(StashPasteboardSnapshot()), .empty)
        XCTAssertEqual(StashPasteboardReader.read(StashPasteboardSnapshot(string: "   \n ")), .empty)
        XCTAssertEqual(StashPasteboardReader.read(StashPasteboardSnapshot(imageData: Data())), .empty)
    }
}
