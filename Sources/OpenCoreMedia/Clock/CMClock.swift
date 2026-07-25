import Synchronization

public final class CMClock: Sendable {
    private let source: any CMClockSource
    private let valid: CMStateLock<Bool>

    public init(source: any CMClockSource) {
        self.source = source
        valid = CMStateLock(true)
    }

    public func time() throws(CMClockError) -> CMTime {
        guard valid.withLock({ $0 }) else {
            throw .invalidated
        }
        let result = try source.currentTime()
        guard valid.withLock({ $0 }) else {
            throw .invalidated
        }
        guard result.isNumeric, result.timescale > 0 else {
            throw .invalidTime
        }
        return result
    }

    public func anchorTime() throws(CMClockError) -> (
        clockTime: CMTime,
        referenceClockTime: CMTime
    ) {
        guard valid.withLock({ $0 }) else {
            throw .invalidated
        }
        let anchor = try source.anchorTime()
        guard valid.withLock({ $0 }) else {
            throw .invalidated
        }
        guard anchor.clockTime.isNumeric,
              anchor.clockTime.timescale > 0,
              anchor.referenceClockTime.isNumeric,
              anchor.referenceClockTime.timescale > 0
        else {
            throw .invalidTime
        }
        return anchor
    }

    public func mightDrift(relativeTo otherClock: CMClock) -> Bool {
        self !== otherClock && (source.mightDrift || otherClock.source.mightDrift)
    }

    public func invalidate() {
        valid.withLock { $0 = false }
    }
}
