public enum CMBufferQueueError: Error, Sendable, Equatable {
    case invalidCapacity(Int)
    case invalidDuration
    case durationOverflow
    case invalidSize(Int)
    case totalSizeOverflow
    case queueIsFull
    case enqueueAfterEndOfData
}
