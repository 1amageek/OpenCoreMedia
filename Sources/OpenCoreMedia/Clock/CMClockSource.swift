public protocol CMClockSource: Sendable {
    var mightDrift: Bool { get }
    func currentTime() throws(CMClockError) -> CMTime
    func anchorTime() throws(CMClockError) -> (
        clockTime: CMTime,
        referenceClockTime: CMTime
    )
}

extension CMClockSource {
    public func anchorTime() throws(CMClockError) -> (
        clockTime: CMTime,
        referenceClockTime: CMTime
    ) {
        throw .anchorUnavailable
    }
}
