import AppKit
import Carbon.HIToolbox
import SwiftData
import XCTest
@testable import Snapper

final class ShellBehaviorTests: XCTestCase {
    // MARK: - Shortcut recording rule

    @MainActor
    func testRecorderRejectsBareAndShiftOnlyKeys() {
        XCTAssertFalse(HotkeyRecorderNSView.isRecordable(keyCode: kVK_ANSI_A, modifiers: []))
        XCTAssertFalse(
            HotkeyRecorderNSView.isRecordable(keyCode: kVK_ANSI_A, modifiers: [.maskShift]),
            "Shift+A as a global shortcut would swallow typing a capital A"
        )
        XCTAssertFalse(HotkeyRecorderNSView.isRecordable(keyCode: kVK_Space, modifiers: [.maskShift]))
    }

    @MainActor
    func testRecorderAcceptsCommandControlOrOption() {
        XCTAssertTrue(HotkeyRecorderNSView.isRecordable(keyCode: kVK_ANSI_A, modifiers: [.maskCommand]))
        XCTAssertTrue(HotkeyRecorderNSView.isRecordable(keyCode: kVK_ANSI_A, modifiers: [.maskControl]))
        XCTAssertTrue(HotkeyRecorderNSView.isRecordable(keyCode: kVK_ANSI_A, modifiers: [.maskAlternate]))
        XCTAssertTrue(HotkeyRecorderNSView.isRecordable(keyCode: kVK_ANSI_4, modifiers: [.maskCommand, .maskShift]))
    }

    @MainActor
    func testRecorderAllowsFunctionKeysWithoutModifiers() {
        for keyCode in [kVK_F1, kVK_F12, kVK_F13, kVK_F19, kVK_F20] {
            XCTAssertTrue(HotkeyRecorderNSView.isRecordable(keyCode: keyCode, modifiers: []), "key code \(keyCode)")
            XCTAssertTrue(
                HotkeyRecorderNSView.isRecordable(keyCode: keyCode, modifiers: [.maskShift]),
                "key code \(keyCode)"
            )
        }
    }

    // MARK: - Key names

    func testFunctionKeysBeyondF12HaveNames() {
        XCTAssertEqual(KeyCodeMap.name(for: kVK_F13), "F13")
        XCTAssertEqual(KeyCodeMap.name(for: kVK_F16), "F16")
        XCTAssertEqual(KeyCodeMap.name(for: kVK_F19), "F19")
        XCTAssertEqual(KeyCodeMap.name(for: kVK_F20), "F20")
    }

    func testNavigationAndEditingKeysHaveNames() {
        XCTAssertEqual(KeyCodeMap.name(for: kVK_Return), "Return")
        XCTAssertEqual(KeyCodeMap.name(for: kVK_Space), "Space")
        XCTAssertEqual(KeyCodeMap.name(for: kVK_Delete), "Delete")
        XCTAssertEqual(KeyCodeMap.name(for: kVK_ForwardDelete), "Forward Delete")
        XCTAssertEqual(KeyCodeMap.name(for: kVK_Home), "Home")
        XCTAssertEqual(KeyCodeMap.name(for: kVK_End), "End")
        XCTAssertEqual(KeyCodeMap.name(for: kVK_PageUp), "Page Up")
        XCTAssertEqual(KeyCodeMap.name(for: kVK_PageDown), "Page Down")
        XCTAssertEqual(KeyCodeMap.name(for: kVK_LeftArrow), "←")
    }

    func testKeypadKeysAreDistinguishableFromMainRow() {
        XCTAssertEqual(KeyCodeMap.name(for: kVK_ANSI_Keypad1), "Keypad 1")
        XCTAssertEqual(KeyCodeMap.name(for: kVK_ANSI_KeypadPlus), "Keypad +")
        XCTAssertEqual(KeyCodeMap.name(for: kVK_ANSI_KeypadEnter), "Keypad Enter")
        XCTAssertNotEqual(KeyCodeMap.name(for: kVK_ANSI_Keypad1), KeyCodeMap.name(for: kVK_ANSI_1))
    }

    func testUnknownKeyCodesFallBackToNumericName() {
        XCTAssertEqual(KeyCodeMap.name(for: 300), "Key300")
        XCTAssertEqual(KeyCodeMap.name(for: -1), "Key-1")
    }

    func testPrintableKeysUseANSINamesOffTheMainThread() {
        XCTAssertEqual(offMainThread { KeyCodeMap.name(for: kVK_ANSI_A) }, "A")
        XCTAssertEqual(offMainThread { KeyCodeMap.name(for: kVK_ANSI_4) }, "4")
        XCTAssertEqual(offMainThread { KeyCodeMap.name(for: kVK_ANSI_Minus) }, "-")
        XCTAssertEqual(offMainThread { KeyCodeMap.name(for: kVK_ANSI_LeftBracket) }, "[")
        XCTAssertEqual(offMainThread { KeyCodeMap.name(for: kVK_ANSI_Grave) }, "`")
    }

    // MARK: - Menu key equivalents

    func testSpecialKeysMapToAppKitKeyEquivalents() {
        XCTAssertEqual(
            KeyCodeMap.menuKeyEquivalent(for: kVK_LeftArrow),
            String(Character(NSEvent.SpecialKey.leftArrow.unicodeScalar)),
            "the display name \"←\" is not the arrow key's equivalent"
        )
        XCTAssertEqual(
            KeyCodeMap.menuKeyEquivalent(for: kVK_DownArrow),
            String(Character(NSEvent.SpecialKey.downArrow.unicodeScalar))
        )
        XCTAssertEqual(KeyCodeMap.menuKeyEquivalent(for: kVK_Return), "\r")
        XCTAssertEqual(KeyCodeMap.menuKeyEquivalent(for: kVK_Tab), "\t")
        XCTAssertEqual(KeyCodeMap.menuKeyEquivalent(for: kVK_Space), " ")
        XCTAssertEqual(
            KeyCodeMap.menuKeyEquivalent(for: kVK_F5),
            String(Character(NSEvent.SpecialKey.f5.unicodeScalar))
        )
        XCTAssertEqual(
            KeyCodeMap.menuKeyEquivalent(for: kVK_F13),
            String(Character(NSEvent.SpecialKey.f13.unicodeScalar))
        )
    }

    func testKeysWithoutAnEquivalentReturnNil() {
        XCTAssertNil(KeyCodeMap.menuKeyEquivalent(for: kVK_ANSI_Keypad1))
        XCTAssertNil(KeyCodeMap.menuKeyEquivalent(for: 300))
    }

    func testPrintableKeyEquivalentsAreLowercase() {
        XCTAssertEqual(offMainThread { KeyCodeMap.menuKeyEquivalent(for: kVK_ANSI_A) }, "a")
        XCTAssertEqual(offMainThread { KeyCodeMap.menuKeyEquivalent(for: kVK_ANSI_4) }, "4")
    }

    // MARK: - History

    @MainActor
    func testUpdateFilePointsRecordAtTheSavedFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShellBehaviorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let manager = HistoryManager(storeURL: directory.appendingPathComponent("History.store"))
        let recordID = UUID()
        let otherID = UUID()
        let context = manager.modelContainer.mainContext
        context.insert(CaptureRecord(id: recordID, captureType: "area", width: 1, height: 1, filePath: ""))
        context.insert(CaptureRecord(id: otherID, captureType: "window", width: 1, height: 1, filePath: ""))
        try context.save()

        let savedURL = directory.appendingPathComponent("saved.png")
        manager.updateFile(recordID: recordID, url: savedURL, fileSize: 1234)

        // The update is applied on the main queue, so a block queued behind
        // it runs once it is done.
        let applied = expectation(description: "update applied")
        DispatchQueue.main.async { applied.fulfill() }
        wait(for: [applied], timeout: 5)

        let records = manager.fetchAll()
        let updated = try XCTUnwrap(records.first { $0.id == recordID })
        XCTAssertEqual(updated.filePath, savedURL.path)
        XCTAssertEqual(updated.fileSize, 1234)

        let untouched = try XCTUnwrap(records.first { $0.id == otherID })
        XCTAssertEqual(untouched.filePath, "")
        XCTAssertEqual(untouched.fileSize, 0)
    }

    // MARK: - Helpers

    /// KeyCodeMap consults the keyboard layout only on the main thread, so a
    /// lookup made elsewhere exercises its layout-independent tables.
    private func offMainThread(_ lookup: @escaping () -> String?) -> String? {
        let result = LookupResult()
        let finished = expectation(description: "lookup finished")
        DispatchQueue.global().async {
            result.value = lookup()
            finished.fulfill()
        }
        wait(for: [finished], timeout: 5)
        return result.value
    }
}

/// Written by the background lookup before it fulfills, read after the wait.
private final class LookupResult: @unchecked Sendable {
    var value: String?
}
