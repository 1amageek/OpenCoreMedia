public enum CMBlockBufferError: Error, Equatable, Sendable {
    case emptyBuffer
    case storageUnavailable
    case invalidCapacity(Int)
    case invalidLength(Int)
    case allocationFailed(length: Int)
    case allocationInProgress
    case concurrentAccessConflict
    case lengthOverflow
    case invalidRange(
        lowerBound: Int,
        upperBound: Int,
        validLowerBound: Int,
        validUpperBound: Int
    )
    case destinationTooSmall(required: Int, actual: Int)
    case sourceTooLarge(maximum: Int, actual: Int)
    case overlappingMemory
    case invalidBlockRange(
        offsetToData: Int,
        dataLength: Int,
        blockLength: Int
    )
    case unsupportedFlags(rawValue: UInt32)
    case nonContiguousStorage
}
