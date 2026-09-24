import Foundation

public struct AudioPacketIntervalMetrics: Sendable {
    public let count: UInt64
    public let minimumNanoseconds: UInt64?
    public let averageNanoseconds: UInt64?
    public let maximumNanoseconds: UInt64?

    public init(
        count: UInt64,
        minimumNanoseconds: UInt64?,
        averageNanoseconds: UInt64?,
        maximumNanoseconds: UInt64?) {
        self.count = count
        self.minimumNanoseconds = minimumNanoseconds
        self.averageNanoseconds = averageNanoseconds
        self.maximumNanoseconds = maximumNanoseconds
    }
}
