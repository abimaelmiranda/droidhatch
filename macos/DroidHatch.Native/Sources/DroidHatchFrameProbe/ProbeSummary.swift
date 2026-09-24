struct ProbeSummary {
    let receivedFrames: Int
    let droppedFrames: UInt64
    let blackSnapshots: Int
    let snapshotCount: Int
    let staleSnapshots: Int
    let timeoutEvents: Int
    let firstSequence: UInt64?
    let lastSequence: UInt64?
}
