public enum CMClockError: Error, Sendable, Equatable {
    case invalidated
    case invalidTime
    case anchorUnavailable
    case invalidRate(Double)
    case timeOverflow
}
