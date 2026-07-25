public enum CMAttachmentValue: Sendable, Equatable {
    case boolean(Bool)
    case integer(Int64)
    case unsignedInteger(UInt64)
    case floatingPoint(Double)
    case string(String)
    case bytes(CMAttachmentBytes)
    case array([CMAttachmentValue])
    case dictionary([String: CMAttachmentValue])
}
