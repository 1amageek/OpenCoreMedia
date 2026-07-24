public enum CMAttachmentValue: Sendable, Equatable {
    // FIXME(INCOMPLETE_IMPLEMENTATION): The public attachment path currently
    // accepts only portable scalar values. Callers reach this type through the
    // Swift bearer overlay and C-derived attachment operations. Arrays,
    // dictionaries, byte payloads, and arbitrary platform objects must not be
    // converted to lossy scalar values or reported as supported before explicit
    // typed cases exist.
    case boolean(Bool)
    case integer(Int64)
    case unsignedInteger(UInt64)
    case floatingPoint(Double)
    case string(String)
}
