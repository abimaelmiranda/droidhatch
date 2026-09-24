import DroidHatchFrameTransport

struct ScrollInputEvent {
    let deltaX: Int32
    let deltaY: Int32
    let phase: InputScrollPhase
    let momentumPhase: InputScrollPhase
    let flags: InputScrollFlags
    let sequence: UInt32
}
