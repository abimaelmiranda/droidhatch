import AppKit
import SwiftUI

@MainActor
public final class DroidHatchViewerController: NSObject, NSWindowDelegate {
    public var onClose: (() -> Void)?

    private var window: ViewerNSWindow?
    private var closeCallbackScheduled = false
    private let powerAssertion = ViewerPowerAssertion()
    private let cursorInactivityController = CursorInactivityController()

    public override init() {
        super.init()
    }

    public func show(configuration: DroidHatchViewerConfiguration) {
        if let existingWindow = window {
            existingWindow.delegate = self
            existingWindow.makeKeyAndOrderFront(nil)
            existingWindow.makeKey()
            NSApp.activate(ignoringOtherApps: true)
            powerAssertion.acquire()
            cursorInactivityController.start()
            NotificationCenter.default.post(name: .droidHatchViewerDidShow, object: nil)
            return
        }

        let options = ViewerOptions(
            host: configuration.host,
            port: configuration.framePort,
            inputHost: configuration.host,
            inputPort: configuration.inputPort,
            audioSocketPath: configuration.audioSocketPath,
            hidesNavigationBar: false,
            prefersMetal: true)
        let contentView = ViewerWindow(options: options)
        let hostingController = NSHostingController(rootView: contentView)
        let window = ViewerNSWindow(
            contentRect: NSRect(origin: .zero, size: ViewerWindowMetrics.initialContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)

        window.title = "DroidHatch"
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenPrimary]
        window.contentViewController = hostingController
        window.minSize = ViewerWindowMetrics.minimumContentSize
        window.maxSize = NSSize(width: 16_384, height: 16_384)
        window.setContentSize(ViewerWindowMetrics.initialContentSize)
        window.center()
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        window.makeKey()
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
        powerAssertion.acquire()
        cursorInactivityController.start()
    }

    public func close() {
        closeCallbackScheduled = false
        if let currentWindow = window {
            currentWindow.delegate = nil
            currentWindow.orderOut(nil)
        }
        tearDown()
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let currentWindow = window, sender === currentWindow else {
            return true
        }

        finishClose()
        currentWindow.orderOut(nil)
        return false
    }

    public func windowWillClose(_ notification: Notification) {
        guard let notificationWindow = notification.object as? ViewerNSWindow,
              notificationWindow === window else {
            return
        }

        finishClose()
    }

    private func tearDown() {
        cursorInactivityController.stop()
        powerAssertion.release()
    }

    private func finishClose() {
        guard !closeCallbackScheduled else {
            return
        }

        closeCallbackScheduled = true
        NotificationCenter.default.post(name: .droidHatchViewerDidClose, object: nil)

        DispatchQueue.main.async { [weak self] in
            guard let self, self.closeCallbackScheduled else {
                return
            }

            self.closeCallbackScheduled = false
            self.cursorInactivityController.stop()
            self.powerAssertion.release()
            self.onClose?()
        }
    }
}
