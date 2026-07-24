public struct CMTimeFlags: OptionSet, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let valid = CMTimeFlags(rawValue: 1 << 0)
    public static let hasBeenRounded = CMTimeFlags(rawValue: 1 << 1)
    public static let positiveInfinity = CMTimeFlags(rawValue: 1 << 2)
    public static let negativeInfinity = CMTimeFlags(rawValue: 1 << 3)
    public static let indefinite = CMTimeFlags(rawValue: 1 << 4)
    public static let impliedValueFlagsMask: CMTimeFlags = [
        .positiveInfinity,
        .negativeInfinity,
        .indefinite,
    ]
}
