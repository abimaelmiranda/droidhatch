public struct InputScrollFlags: OptionSet, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let precise = Self(rawValue: 1)
    public static let momentum = Self(rawValue: 2)
    public static let directionInverted = Self(rawValue: 4)
}
