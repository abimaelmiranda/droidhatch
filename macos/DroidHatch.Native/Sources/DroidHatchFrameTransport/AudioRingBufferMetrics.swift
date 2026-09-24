import Foundation

public struct AudioRingBufferMetrics: Sendable {
    public let capacityFrames: Int
    public let occupiedFrames: Int
    public let minimumOccupiedFrames: Int
    public let maximumOccupiedFrames: Int
    public let totalWrittenFrames: UInt64
    public let totalReadFrames: UInt64
    public let underrunFrames: UInt64
    public let underrunEvents: UInt64
    public let overflowFrames: UInt64
    public let playbackStarted: Bool

    public init(
        capacityFrames: Int,
        occupiedFrames: Int,
        minimumOccupiedFrames: Int,
        maximumOccupiedFrames: Int,
        totalWrittenFrames: UInt64,
        totalReadFrames: UInt64,
        underrunFrames: UInt64,
        underrunEvents: UInt64,
        overflowFrames: UInt64,
        playbackStarted: Bool) {
        self.capacityFrames = capacityFrames
        self.occupiedFrames = occupiedFrames
        self.minimumOccupiedFrames = minimumOccupiedFrames
        self.maximumOccupiedFrames = maximumOccupiedFrames
        self.totalWrittenFrames = totalWrittenFrames
        self.totalReadFrames = totalReadFrames
        self.underrunFrames = underrunFrames
        self.underrunEvents = underrunEvents
        self.overflowFrames = overflowFrames
        self.playbackStarted = playbackStarted
    }
}
