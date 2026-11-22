import AppKit
import ApplicationServices
import CoreGraphics

struct PasteboardSnapshot: Equatable {
    struct ItemData: Equatable {
        let typesAndData: [(NSPasteboard.PasteboardType, Data)]

        static func == (lhs: ItemData, rhs: ItemData) -> Bool {
            guard lhs.typesAndData.count == rhs.typesAndData.count else { return false }
            for (l, r) in zip(lhs.typesAndData, rhs.typesAndData) {
                if l.0 != r.0 || l.1 != r.1 { return false }
            }
            return true
        }
    }

    let items: [ItemData]
}

protocol PasteboardControlling: AnyObject {
    var changeCount: Int { get }
    func captureSnapshot() -> PasteboardSnapshot
    func restoreSnapshot(_ snapshot: PasteboardSnapshot)
    @discardableResult func writeString(_ string: String) -> Int
}

final class SystemPasteboardController: PasteboardControlling {
    static let shared = SystemPasteboardController()
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int {
        pasteboard.changeCount
    }

    func captureSnapshot() -> PasteboardSnapshot {
        let items: [PasteboardSnapshot.ItemData] = (pasteboard.pasteboardItems ?? []).map { item in
            var pairs: [(NSPasteboard.PasteboardType, Data)] = []
            for type in item.types {
                if let data = item.data(forType: type) {
                    pairs.append((type, data))
                }
            }
            return PasteboardSnapshot.ItemData(typesAndData: pairs)
        }
        return PasteboardSnapshot(items: items)
    }

    func restoreSnapshot(_ snapshot: PasteboardSnapshot) {
        pasteboard.clearContents()
        guard !snapshot.items.isEmpty else { return }

        var pbItems: [NSPasteboardItem] = []
        for entry in snapshot.items {
            let item = NSPasteboardItem()
            for (type, data) in entry.typesAndData {
                item.setData(data, forType: type)
            }
            pbItems.append(item)
        }
        pasteboard.writeObjects(pbItems)
    }

    @discardableResult
    func writeString(_ string: String) -> Int {
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        return pasteboard.changeCount
    }
}

enum TextInjector {
    static func copyToClipboard(_ text: String, pasteboard: PasteboardControlling = SystemPasteboardController.shared) {
        pasteboard.writeString(text)
    }

    /// Проверяет, есть ли под курсором редактируемое поле (требует Accessibility).
    static func canPasteIntoFocusedField() -> Bool {
        guard AXIsProcessTrusted() else { return false }

        let systemWide = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        let status = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused)
        guard status == .success, let element = focused else { return false }
        let axElement = element as! AXUIElement

        var valueSettable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(axElement, kAXValueAttribute as CFString, &valueSettable) == .success,
           valueSettable.boolValue {
            return true
        }

        var selectedSettable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(axElement, kAXSelectedTextAttribute as CFString, &selectedSettable) == .success,
           selectedSettable.boolValue {
            return true
        }

        return false
    }

    static func pasteAtCursor() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    /// Вставляет текст в активное поле (если возможно) или оставляет в буфере обмена.
    /// При успешной автовставке с `restoreClipboard == true` восстанавливает прежнее содержимое буфера через `restoreDelay`.
    static func insert(
        text: String,
        mode: PasteMode,
        restoreClipboard: Bool,
        restoreDelay: TimeInterval = 0.4,
        pasteboard: PasteboardControlling = SystemPasteboardController.shared,
        canPaste: () -> Bool = { PermissionsHelper.accessibilityAuthorized() && canPasteIntoFocusedField() },
        performPaste: () -> Void = { pasteAtCursor() },
        scheduler: (@escaping () -> Void) -> Void = { work in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
        }
    ) -> InsertStatus {
        guard mode == .autoPaste, canPaste() else {
            pasteboard.writeString(text)
            return .clipboardOnly
        }

        let snapshot = restoreClipboard ? pasteboard.captureSnapshot() : nil
        let writtenChangeCount = pasteboard.writeString(text)
        performPaste()

        if let snapshot {
            let restoreWork = {
                // Не затираем буфер, если за 400 мс пользователь или другая диктовка успели туда что-то записать.
                if pasteboard.changeCount == writtenChangeCount {
                    pasteboard.restoreSnapshot(snapshot)
                }
            }
            if restoreDelay == 0.4 {
                scheduler(restoreWork)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay, execute: restoreWork)
            }
        }

        return .inserted
    }
}
