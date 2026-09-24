import MetalKit
import SwiftUI

struct MetalFrameViewRepresentable: NSViewRepresentable {
    let surface: MetalFrameSurface

    func makeNSView(context: Context) -> MetalFrameView {
        MetalFrameView(surface: surface)
    }

    func updateNSView(_ nsView: MetalFrameView, context: Context) {}
}
