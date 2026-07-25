public enum CMSimpleQueueError: Error, Sendable, Equatable {
    case invalidCapacity(Int)
    case queueIsFull
}
