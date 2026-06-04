import AppKit
import SwiftUI

@MainActor
final class PanelController {
    private let panel: NSPanel
    let store: DesktopStore
    private var globalClickMonitor: Any?
    private var localKeyMonitor: Any?

    init() {
        let store = DesktopStore()
        self.store = store

        let content = NSHostingView(rootView: ContentView(store: store))
        content.translatesAutoresizingMaskIntoConstraints = false

        let initialRect = NSRect(x: 0, y: 0, width: 360, height: 420)
        let panel = NSPanel(
            contentRect: initialRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isMovable = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let visual = NSVisualEffectView()
        visual.translatesAutoresizingMaskIntoConstraints = false
        visual.material = .popover
        visual.blendingMode = .behindWindow
        visual.state = .active
        visual.wantsLayer = true
        visual.layer?.cornerRadius = 12
        visual.layer?.masksToBounds = true

        let container = NSView(frame: initialRect)
        container.addSubview(visual)
        container.addSubview(content)
        NSLayoutConstraint.activate([
            visual.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            visual.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            visual.topAnchor.constraint(equalTo: container.topAnchor),
            visual.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            content.topAnchor.constraint(equalTo: container.topAnchor),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        panel.contentView = container

        self.panel = panel
    }

    var isVisible: Bool { panel.isVisible }

    func toggle(relativeTo button: NSStatusBarButton?) {
        if panel.isVisible {
            hide()
        } else {
            show(relativeTo: button)
        }
    }

    func show(relativeTo button: NSStatusBarButton?) {
        store.refresh()
        positionPanel(relativeTo: button)
        panel.orderFrontRegardless()
        installEventMonitors()
    }

    func hide() {
        removeEventMonitors()
        panel.orderOut(nil)
    }

    private func positionPanel(relativeTo button: NSStatusBarButton?) {
        guard let button = button, let buttonWindow = button.window else {
            panel.center()
            return
        }
        let buttonRectInScreen = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let panelSize = panel.frame.size
        let gap: CGFloat = 6
        var origin = NSPoint(
            x: buttonRectInScreen.midX - panelSize.width / 2,
            y: buttonRectInScreen.minY - panelSize.height - gap
        )
        if let screen = buttonWindow.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = max(visible.minX + 8, min(origin.x, visible.maxX - panelSize.width - 8))
            origin.y = max(visible.minY + 8, origin.y)
        }
        panel.setFrameOrigin(origin)
    }

    private func installEventMonitors() {
        removeEventMonitors()
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 {
                self?.hide()
                return nil
            }
            return event
        }
    }

    private func removeEventMonitors() {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
    }
}

