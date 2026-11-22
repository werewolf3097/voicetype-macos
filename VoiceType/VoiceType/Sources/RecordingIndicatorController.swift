import AppKit
import SwiftUI

enum IndicatorLayoutCalculator {
    static func frame(
        size: CGSize,
        screenFrame: NSRect,
        visibleFrame: NSRect,
        safeAreaTop: CGFloat,
        auxTopLeft: NSRect,
        auxTopRight: NSRect,
        position: IndicatorPosition,
        placement: IndicatorPlacement
    ) -> NSRect? {
        guard position != .off else { return nil }

        let centerX = screenFrame.midX - size.width / 2

        if position == .bottom {
            let y = visibleFrame.minY + 14
            return NSRect(x: centerX, y: y, width: size.width, height: size.height)
        }

        // position == .top
        let hasNotch = safeAreaTop > 0 && (!auxTopLeft.isEmpty || !auxTopRight.isEmpty)
        let menuBarHeight = max(24, screenFrame.maxY - visibleFrame.maxY)

        switch placement {
        case .fromNotch:
            if hasNotch {
                // Выезжает прямо из-под выреза (notch)
                let y = screenFrame.maxY - safeAreaTop - size.height - 4
                return NSRect(x: centerX, y: y, width: size.width, height: size.height)
            } else {
                // На Mac без выреза ведёт себя как «под строкой меню»
                let y = visibleFrame.maxY - size.height - 8
                return NSRect(x: centerX, y: y, width: size.width, height: size.height)
            }

        case .inMenuBar:
            if hasNotch && !auxTopRight.isEmpty {
                // Не перекрываем аппаратный вырез: размещаем в начале правой области строки меню
                let x = min(
                    auxTopRight.minX + 10,
                    screenFrame.maxX - size.width - 12
                )
                let y = screenFrame.maxY - menuBarHeight + (menuBarHeight - size.height) / 2
                return NSRect(x: x, y: y, width: size.width, height: size.height)
            } else {
                let y = screenFrame.maxY - menuBarHeight + (menuBarHeight - size.height) / 2
                return NSRect(x: centerX, y: y, width: size.width, height: size.height)
            }

        case .belowMenuBar:
            let y = visibleFrame.maxY - size.height - 8
            return NSRect(x: centerX, y: y, width: size.width, height: size.height)
        }
    }
}

/// Временная плавающая панель поверх всех окон и Spaces.
/// В покое панель не создаётся и не рисуется вообще (`orderOut` + освобождение).
@MainActor
final class RecordingIndicatorController {
    private var panel: NSPanel?
    private var hideWorkItem: DispatchWorkItem?
    private let model = RecordingIndicatorModel()
    private weak var settings: SettingsStore?

    func configure(settings: SettingsStore) {
        self.settings = settings
        model.processingLook = settings.processingLook
    }

    func updateAudioLevel(_ level: Float) {
        guard model.state == .recording else { return }
        model.pushLevel(level)
    }

    func update(
        status: RecordingStatus,
        targetApp: String?,
        insertOutcome: InsertStatus?
    ) {
        hideWorkItem?.cancel()
        hideWorkItem = nil

        if let settings {
            model.processingLook = settings.processingLook
            if settings.indicatorPosition == .off {
                hideNow()
                return
            }
        }

        switch status {
        case .idle:
            // Если только что завершилась вставка — показываем подтверждение, иначе скрываем.
            if let insertOutcome {
                switch insertOutcome {
                case .inserted:
                    model.state = .inserted(targetApp: targetApp)
                    showCurrentState()
                    scheduleHide(after: 1.0)
                case .clipboardOnly:
                    model.state = .clipboardOnly(targetApp: targetApp)
                    showCurrentState()
                    scheduleHide(after: 2.8)
                case .failed:
                    hideNow()
                }
            } else {
                hideNow()
            }

        case .recording:
            model.resetLevels()
            model.state = .recording
            showCurrentState()

        case .transcribing:
            model.state = .transcribing(targetApp: targetApp)
            showCurrentState()

        case .cleaning:
            model.state = .cleaning(targetApp: targetApp)
            showCurrentState()

        case .error(let message):
            model.state = .error(message)
            showCurrentState()
            scheduleHide(after: 3.0)
        }
    }

    private func scheduleHide(after delay: TimeInterval) {
        let workItem = DispatchWorkItem { [weak self] in
            self?.hideNow()
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func hideNow() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        model.state = .hidden
        model.resetLevels()
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
    }

    private func showCurrentState() {
        guard let settings, settings.indicatorPosition != .off else {
            hideNow()
            return
        }

        let panel = self.panel ?? makePanel()
        self.panel = panel
        if let hosting = panel.contentView as? NSHostingView<AnyView> {
            hosting.rootView = makeRootView()
            hosting.layoutSubtreeIfNeeded()
        }
        position(panel)
        panel.orderFrontRegardless()
    }

    private func makeRootView() -> AnyView {
        let baseView = RecordingIndicatorView(model: model)
        if let settings {
            return AnyView(baseView.applyPaperEnvironment(settings))
        }
        return AnyView(baseView)
    }

    private func makePanel() -> NSPanel {
        let hosting = NSHostingView(rootView: makeRootView())
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 28),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.contentView = hosting
        return panel
    }

    private func position(_ panel: NSPanel) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
        guard let screen else { return }

        let fittingSize = panel.contentView?.fittingSize ?? NSSize(width: 100, height: 26)
        panel.setContentSize(fittingSize)

        let pos = settings?.indicatorPosition ?? .top
        let placement = settings?.indicatorPlacement ?? .fromNotch

        let safeTop = screen.safeAreaInsets.top
        let auxLeft = screen.auxiliaryTopLeftArea ?? .zero
        let auxRight = screen.auxiliaryTopRightArea ?? .zero

        guard let targetFrame = IndicatorLayoutCalculator.frame(
            size: fittingSize,
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaTop: safeTop,
            auxTopLeft: auxLeft,
            auxTopRight: auxRight,
            position: pos,
            placement: placement
        ) else {
            return
        }

        panel.setFrameOrigin(targetFrame.origin)
    }
}
