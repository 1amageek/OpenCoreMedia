public struct CMMediaType: RawRepresentable, Sendable, Hashable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let video = CMMediaType(rawValue: 0x7669_6465)
}
