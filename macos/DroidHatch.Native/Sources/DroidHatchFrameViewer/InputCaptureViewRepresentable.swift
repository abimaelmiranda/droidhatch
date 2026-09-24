import AppKit
import DroidHatchFrameTransport
import SwiftUI

@MainActor
struct InputCaptureViewRepresentable: NSViewRepresentable {
    let frameSize: CGSize?
    let sendKey: (UInt16, InputKeyAction) -> Void
    let sendTouch: (InputTouchAction, UInt32, UInt32) -> Void
    let sendScroll: (ScrollInputEvent) -> Void
    let sendSystemAction: (InputSystemAction) -> Void

    func makeNSView(context: Context) -> InputCaptureView {
        let view = InputCaptureView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: InputCaptureView, context: Context) {
        update(nsView)
    }

    private func update(_ view: InputCaptureView) {
        view.frameSize = frameSize
        view.sendKey = sendKey
        view.sendTouch = sendTouch
        view.sendScroll = sendScroll
        view.sendSystemAction = sendSystemAction
    }
}
