import Foundation

enum ViewerRuntimeDefaults {
    static let audioMetricsIntervalNanoseconds: UInt64 = 5_000_000_000
    static let videoMetricsWindowNanoseconds: UInt64 = 1_000_000_000
    static let initialRetryDelayNanoseconds: UInt64 = 250_000_000
    static let maximumRetryDelayNanoseconds: UInt64 = 2_000_000_000
    static let frameReadTimeoutSeconds: Double = 5
    static let inputConnectionPollIntervalNanoseconds: UInt64 = 500_000_000
    static let retryMultiplier: UInt64 = 2
    static let nanosecondsPerSecond: Double = 1_000_000_000
    static let nanosecondsPerMillisecond: Double = 1_000_000

    static let rgbaBytesPerPixel: UInt32 = 4
    static let defaultPointerId: UInt32 = 0
}
