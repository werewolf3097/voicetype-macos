import AppKit
import XCTest
@testable import VoiceTypeTests

final class Phase2CoreTests: XCTestCase {
    // MARK: - HotkeyStateMachine

    func testHoldOrDoubleTapLongHoldPushToTalk() {
        var sm = HotkeyStateMachine(mode: .holdOrDoubleTap, holdThreshold: 0.25, doubleTapWindow: 0.30)

        XCTAssertEqual(sm.handleModifierDown(at: 10.0, isSystemRecording: false), [])
        XCTAssertEqual(sm.nextDeadline, 10.25)

        // До порога 250 мс запись не начинается
        XCTAssertEqual(sm.tick(at: 10.20), [])
        // В момент 250 мс стартует push-to-talk
        XCTAssertEqual(sm.tick(at: 10.25), [.startRecording])
        // Отпускание завершает запись
        XCTAssertEqual(sm.handleModifierUp(at: 11.5), [.stopRecording])
        XCTAssertEqual(sm.phase, .idle)
    }

    func testHoldOrDoubleTapDoubleTapHandsFree() {
        var sm = HotkeyStateMachine(mode: .holdOrDoubleTap, holdThreshold: 0.25, doubleTapWindow: 0.30)

        // Первое короткое нажатие
        XCTAssertEqual(sm.handleModifierDown(at: 1.00, isSystemRecording: false), [])
        XCTAssertEqual(sm.handleModifierUp(at: 1.08), [])
        XCTAssertEqual(sm.phase, .waitingSecondTap(releasedAt: 1.08))

        // Второе нажатие в пределах 300 мс включает hands-free
        XCTAssertEqual(sm.handleModifierDown(at: 1.25, isSystemRecording: false), [.startRecording])
        XCTAssertEqual(sm.handleModifierUp(at: 1.32), [])
        XCTAssertEqual(sm.phase, .handsFreeRecording)

        // Третье нажатие останавливает запись
        XCTAssertEqual(sm.handleModifierDown(at: 5.00, isSystemRecording: true), [.stopRecording])
        XCTAssertEqual(sm.handleModifierUp(at: 5.08), [])
        XCTAssertEqual(sm.phase, .idle)
    }

    func testHoldOrDoubleTapExpiredWindowDoesNotTriggerHandsFree() {
        var sm = HotkeyStateMachine(mode: .holdOrDoubleTap, holdThreshold: 0.25, doubleTapWindow: 0.30)

        XCTAssertEqual(sm.handleModifierDown(at: 1.00, isSystemRecording: false), [])
        XCTAssertEqual(sm.handleModifierUp(at: 1.08), [])
        XCTAssertEqual(sm.tick(at: 1.40), [])
        XCTAssertEqual(sm.phase, .idle)

        // Следующий тап уже не считается вторым
        XCTAssertEqual(sm.handleModifierDown(at: 1.45, isSystemRecording: false), [])
        XCTAssertEqual(sm.handleModifierUp(at: 1.52), [])
        XCTAssertEqual(sm.phase, .waitingSecondTap(releasedAt: 1.52))
    }

    func testChordOtherKeyCancelsModifierWithoutStartingRecording() {
        var sm = HotkeyStateMachine(mode: .holdOrDoubleTap, holdThreshold: 0.25, doubleTapWindow: 0.30)

        XCTAssertEqual(sm.handleModifierDown(at: 2.00, isSystemRecording: false), [])
        // Пользователь нажал букву (например, ⌥ + A)
        XCTAssertEqual(sm.handleOtherKeyDown(isEscape: false), [])
        XCTAssertEqual(sm.tick(at: 2.40), [])
        XCTAssertEqual(sm.handleModifierUp(at: 2.50), [])
        XCTAssertEqual(sm.phase, .idle)
    }

    func testToggleModeAndEscapeCancel() {
        var sm = HotkeyStateMachine(mode: .toggle)

        // Аккорд ⌥ + буква не должен запускать запись
        XCTAssertEqual(sm.handleModifierDown(at: 1.0, isSystemRecording: false), [])
        XCTAssertEqual(sm.handleOtherKeyDown(isEscape: false), [])
        XCTAssertEqual(sm.handleModifierUp(at: 1.1), [])

        // Чистый клик запускает запись на отпускании
        XCTAssertEqual(sm.handleModifierDown(at: 2.0, isSystemRecording: false), [])
        XCTAssertEqual(sm.handleModifierUp(at: 2.1), [.startRecording])

        // Escape отменяет запись
        XCTAssertEqual(sm.handleOtherKeyDown(isEscape: true), [.cancelRecording])
        XCTAssertEqual(sm.phase, .idle)
    }

    func testHoldModeRespectsChordGrace() {
        var sm = HotkeyStateMachine(mode: .hold, holdThreshold: 0.25, doubleTapWindow: 0.30, holdChordGrace: 0.10)

        // Быстрый аккорд до истечения 100 мс отменяется
        XCTAssertEqual(sm.handleModifierDown(at: 1.00, isSystemRecording: false), [])
        XCTAssertEqual(sm.handleOtherKeyDown(isEscape: false), [])
        XCTAssertEqual(sm.tick(at: 1.20), [])
        XCTAssertEqual(sm.handleModifierUp(at: 1.25), [])

        // Удержание без других клавиш стартует после grace и стопается при отпускании
        XCTAssertEqual(sm.handleModifierDown(at: 2.00, isSystemRecording: false), [])
        XCTAssertEqual(sm.tick(at: 2.10), [.startRecording])
        XCTAssertEqual(sm.handleModifierUp(at: 2.80), [.stopRecording])
    }

    // MARK: - Settings Migration

    func testSettingsMigrationFromLegacyDefaults() throws {
        let suiteName = "com.farrukh.voicetype.tests.settings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("Right Command", forKey: "hotkey")
        defaults.set("По нажатию (старт / стоп)", forKey: "recordingMode")
        defaults.set(false, forKey: "autoPaste")

        let store = SettingsStore(defaults: defaults, persistSecrets: false, syncDockIcon: false)
        XCTAssertEqual(store.shortcutKey, .command)
        XCTAssertEqual(store.shortcutSide, .right)
        XCTAssertEqual(store.shortcutMode, .toggle)
        XCTAssertEqual(store.pasteMode, .clipboardOnly)
        XCTAssertTrue(store.restoreClipboard)
    }

    // MARK: - HistoryStore Backward Compatibility

    func testLegacyHistoryJSONDecodesWithDefaultInsertStatus() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("history.json")
        let legacyJSON = """
        [
          {
            "id": "11111111-1111-1111-1111-111111111111",
            "date": "2026-10-19T12:00:00Z",
            "text": "Привет мир",
            "durationSeconds": 3.5,
            "engine": "gapi"
          }
        ]
        """
        try legacyJSON.data(using: .utf8)!.write(to: fileURL)

        let store = HistoryStore(fileURL: fileURL)
        XCTAssertEqual(store.records.count, 1)
        let record = try XCTUnwrap(store.records.first)
        XCTAssertEqual(record.text, "Привет мир")
        XCTAssertEqual(record.status, .inserted)
        XCTAssertNil(record.targetApp)
        XCTAssertNil(record.errorMessage)
        XCTAssertNil(record.style)
    }

    func testFailedEmptyRecordIsSavedToHistory() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("history.json")
        let store = HistoryStore(fileURL: fileURL)
        store.add(
            text: "",
            durationSeconds: 1.2,
            status: .failed,
            targetApp: "Telegram",
            errorMessage: "Не удалось распознать (тишина)",
            style: .friendly
        )

        let reloaded = HistoryStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.records.count, 1)
        XCTAssertEqual(reloaded.records.first?.status, .failed)
        XCTAssertEqual(reloaded.records.first?.text, "")
        XCTAssertEqual(reloaded.records.first?.errorMessage, "Не удалось распознать (тишина)")
        XCTAssertEqual(reloaded.records.first?.targetApp, "Telegram")
    }

    // MARK: - DictionaryStore

    func testDictionaryAppliesReplacementsOnWordBoundaries() {
        let entries = [
            DictionaryEntry(heard: "эпам", written: "EPAM"),
            DictionaryEntry(heard: "корзинка", written: "Korzinka")
        ]
        let result = DictionaryStore.apply(
            entries: entries,
            to: "Вчера созвон с Эпам и корзинка прошёл хорошо."
        )
        XCTAssertEqual(result, "Вчера созвон с EPAM и Korzinka прошёл хорошо.")
    }

    // MARK: - TextInjector Clipboard Snapshot & Restore

    func testTextInjectorRestoresMultiTypeSnapshotAfterAutoPaste() {
        let pb = InMemoryPasteboard()
        let rtfType = NSPasteboard.PasteboardType.rtf
        let rtfData = Data("{\\rtf1 old}".utf8)
        let textData = Data("old text".utf8)
        pb.items = [PasteboardSnapshot.ItemData(typesAndData: [(.string, textData), (rtfType, rtfData)])]

        var scheduledWork: (() -> Void)?
        var pasted = false

        let status = TextInjector.insert(
            text: "новая диктовка",
            mode: .autoPaste,
            restoreClipboard: true,
            pasteboard: pb,
            canPaste: { true },
            performPaste: { pasted = true },
            scheduler: { work in scheduledWork = work }
        )

        XCTAssertEqual(status, .inserted)
        XCTAssertTrue(pasted)
        XCTAssertEqual(pb.currentString, "новая диктовка")

        scheduledWork?()
        XCTAssertEqual(pb.items.count, 1)
        XCTAssertEqual(pb.currentString, "old text")
        XCTAssertEqual(pb.items.first?.typesAndData.last?.1, rtfData)
    }

    func testTextInjectorDoesNotRestoreIfClipboardChangedExternally() {
        let pb = InMemoryPasteboard()
        pb.items = [PasteboardSnapshot.ItemData(typesAndData: [(.string, Data("old".utf8))])]

        var scheduledWork: (() -> Void)?
        let status = TextInjector.insert(
            text: "диктовка",
            mode: .autoPaste,
            restoreClipboard: true,
            pasteboard: pb,
            canPaste: { true },
            performPaste: {},
            scheduler: { work in scheduledWork = work }
        )

        XCTAssertEqual(status, .inserted)
        pb.writeString("скопировал пользователь")
        scheduledWork?()
        XCTAssertEqual(pb.currentString, "скопировал пользователь")
    }

    func testTextInjectorLeavesTextInClipboardWhenCannotPaste() {
        let pb = InMemoryPasteboard()
        pb.items = [PasteboardSnapshot.ItemData(typesAndData: [(.string, Data("old".utf8))])]

        var pasted = false
        let status = TextInjector.insert(
            text: "текст для ручной вставки",
            mode: .autoPaste,
            restoreClipboard: true,
            pasteboard: pb,
            canPaste: { false },
            performPaste: { pasted = true },
            scheduler: { _ in XCTFail("Should not schedule restore on clipboardOnly fallback") }
        )

        XCTAssertEqual(status, .clipboardOnly)
        XCTAssertFalse(pasted)
        XCTAssertEqual(pb.currentString, "текст для ручной вставки")
    }
}

private final class InMemoryPasteboard: PasteboardControlling {
    var changeCount: Int = 1
    var items: [PasteboardSnapshot.ItemData] = []

    var currentString: String? {
        for item in items {
            for (type, data) in item.typesAndData where type == .string {
                return String(data: data, encoding: .utf8)
            }
        }
        return nil
    }

    func captureSnapshot() -> PasteboardSnapshot {
        PasteboardSnapshot(items: items)
    }

    func restoreSnapshot(_ snapshot: PasteboardSnapshot) {
        changeCount += 1
        items = snapshot.items
    }

    @discardableResult
    func writeString(_ string: String) -> Int {
        changeCount += 1
        items = [PasteboardSnapshot.ItemData(typesAndData: [(.string, Data(string.utf8))])]
        return changeCount
    }
}
