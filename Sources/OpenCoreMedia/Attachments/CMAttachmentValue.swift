public enum CMAttachmentValue: Sendable, Equatable {
    // FIXME(INCOMPLETE_IMPLEMENTATION): The public attachment path currently
    // accepts portable scalar and recursively typed collection values. Callers
    // reach this type through buffer and per-sample attachment operations. Byte
    // payloads and arbitrary platform objects must not be copied into ad hoc
    // arrays or reported as supported before explicit ownership-bearing cases
    // exist.
    case boolean(Bool)
    case integer(Int64)
    case unsignedInteger(UInt64)
    case floatingPoint(Double)
    case string(String)
    case array([CMAttachmentValue])
    case dictionary([String: CMAttachmentValue])
}
