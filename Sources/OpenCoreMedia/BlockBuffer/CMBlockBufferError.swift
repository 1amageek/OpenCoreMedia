public enum CMBlockBufferError: Error, Equatable, Sendable {
    case emptyBuffer
    case storageUnavailable
    case invalidRange(
        lowerBound: Int,
        upperBound: Int,
        validLowerBound: Int,
        validUpperBound: Int
    )
    case destinationTooSmall(required: Int, actual: Int)
    case sourceTooLarge(maximum: Int, actual: Int)
    case unsupportedFlags(rawValue: UInt32)
    case nonContiguousStorage
}
