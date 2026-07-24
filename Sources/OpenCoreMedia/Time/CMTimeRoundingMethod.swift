public enum CMTimeRoundingMethod: UInt32, Sendable {
    case roundHalfAwayFromZero = 1
    case roundTowardZero = 2
    case roundAwayFromZero = 3
    case quickTime = 4
    case roundTowardPositiveInfinity = 5
    case roundTowardNegativeInfinity = 6

    public static var `default`: CMTimeRoundingMethod {
        .roundHalfAwayFromZero
    }
}
