import Foundation

enum Fsr1RenderDefaults {
    static let minimumScale: CGFloat = 1.0
    static let maximumScale: CGFloat = 2
    static let defaultOutputScale = 1.5
    static let defaultSharpness = 0.375
    static let minimumSharpness = 0.0
    static let maximumSharpness = 1.0
    static let sharpnessStopRange: Float = 2
    static let scaleStep = 0.05
    static let sharpnessStep = 0.05
    static let threadgroupWidth = 8
    static let threadgroupHeight = 8
}
