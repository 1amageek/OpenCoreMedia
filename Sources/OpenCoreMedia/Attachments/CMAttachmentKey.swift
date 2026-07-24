public struct CMAttachmentKey:
    RawRepresentable,
    Sendable,
    Hashable
{
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
