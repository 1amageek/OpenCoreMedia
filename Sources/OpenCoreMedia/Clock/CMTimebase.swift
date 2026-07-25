import Synchronization

public final class CMTimebase: Sendable {
    public enum Source: Sendable {
        case clock(CMClock)
        case timebase(CMTimebase)
    }

    private struct State: Sendable {
        var rate: Double
        var anchorTime: CMTime
        var anchorSourceTime: CMTime
        var revision: UInt64
    }

    public let source: Source
    private let state: CMStateLock<State>

    public init(sourceClock: CMClock) throws(CMClockError) {
        source = .clock(sourceClock)
        state = CMStateLock(State(
            rate: 0,
            anchorTime: .zero,
            anchorSourceTime: try sourceClock.time(),
            revision: 0
        ))
    }

    public init(sourceTimebase: CMTimebase) throws(CMClockError) {
        source = .timebase(sourceTimebase)
        state = CMStateLock(State(
            rate: 0,
            anchorTime: .zero,
            anchorSourceTime: try sourceTimebase.time(),
            revision: 0
        ))
    }

    public var rate: Double {
        state.withLock { $0.rate }
    }

    public func time() throws(CMClockError) -> CMTime {
        while true {
            let snapshot = state.withLock { $0 }
            let sourceTime = try currentSourceTime()
            let isCurrent = state.withLock {
                $0.revision == snapshot.revision
            }
            if isCurrent {
                return try Self.time(
                    at: sourceTime,
                    state: snapshot
                )
            }
        }
    }

    public func setTime(_ time: CMTime) throws(CMClockError) {
        guard time.isNumeric, time.timescale > 0 else {
            throw .invalidTime
        }
        while true {
            let revision = state.withLock { $0.revision }
            let sourceTime = try currentSourceTime()
            let installed = state.withLock { state in
                guard state.revision == revision else {
                    return false
                }
                state.anchorTime = time
                state.anchorSourceTime = sourceTime
                state.revision &+= 1
                return true
            }
            if installed {
                return
            }
        }
    }

    public func setRate(_ rate: Double) throws(CMClockError) {
        guard rate.isFinite else {
            throw .invalidRate(rate)
        }
        while true {
            let snapshot = state.withLock { $0 }
            let sourceTime = try currentSourceTime()
            let anchoredTime = try Self.time(
                at: sourceTime,
                state: snapshot
            )
            let installed = state.withLock { state in
                guard state.revision == snapshot.revision else {
                    return false
                }
                state.anchorTime = anchoredTime
                state.anchorSourceTime = sourceTime
                state.rate = rate
                state.revision &+= 1
                return true
            }
            if installed {
                return
            }
        }
    }

    @available(
        *,
        deprecated,
        message: "Use setRateAndAnchorTime(rate:anchorTime:referenceTime:)"
    )
    public func setRate(
        _ rate: Double,
        time: CMTime,
        atSourceTime sourceTime: CMTime
    ) throws(CMClockError) {
        try setRateAndAnchorTime(
            rate: rate,
            anchorTime: time,
            referenceTime: sourceTime
        )
    }

    public func setRateAndAnchorTime(
        rate: Double,
        anchorTime time: CMTime,
        referenceTime sourceTime: CMTime
    ) throws(CMClockError) {
        guard rate.isFinite else {
            throw .invalidRate(rate)
        }
        guard time.isNumeric,
              sourceTime.isNumeric,
              time.timescale > 0,
              sourceTime.timescale > 0
        else {
            throw .invalidTime
        }
        state.withLock { state in
            state.rate = rate
            state.anchorTime = time
            state.anchorSourceTime = sourceTime
            state.revision &+= 1
        }
    }

    public var effectiveRate: Double {
        switch source {
        case .clock:
            return rate
        case .timebase(let sourceTimebase):
            return rate * sourceTimebase.effectiveRate
        }
    }

    public var ultimateSourceClock: CMClock {
        switch source {
        case .clock(let clock):
            return clock
        case .timebase(let sourceTimebase):
            return sourceTimebase.ultimateSourceClock
        }
    }

    private func currentSourceTime() throws(CMClockError) -> CMTime {
        switch source {
        case .clock(let clock):
            return try clock.time()
        case .timebase(let timebase):
            return try timebase.time()
        }
    }

    private static func time(
        at sourceTime: CMTime,
        state: State
    ) throws(CMClockError) -> CMTime {
        if state.rate == 0 {
            return state.anchorTime
        }
        let delta = sourceTime - state.anchorSourceTime
        guard delta.isNumeric, delta.timescale > 0 else {
            throw .invalidTime
        }
        if state.rate == 1 {
            let result = state.anchorTime + delta
            guard result.isNumeric else {
                throw .timeOverflow
            }
            return result
        }
        if state.rate == -1 {
            let (negatedValue, overflow) =
                Int64.zero.subtractingReportingOverflow(delta.value)
            guard !overflow else {
                throw .timeOverflow
            }
            let result = state.anchorTime + CMTime(
                value: negatedValue,
                timescale: delta.timescale
            )
            guard result.isNumeric else {
                throw .timeOverflow
            }
            return result
        }
        let scaledSeconds = delta.seconds * state.rate
        guard scaledSeconds.isFinite else {
            throw .timeOverflow
        }
        let scaledValue = scaledSeconds * Double(delta.timescale)
        let roundedValue = scaledValue.rounded()
        let exclusiveUpperBound = -Double(Int64.min)
        guard roundedValue >= Double(Int64.min),
              roundedValue < exclusiveUpperBound
        else {
            throw .timeOverflow
        }
        let scaledDelta = CMTime(
            value: Int64(roundedValue),
            timescale: delta.timescale
        )
        let result = state.anchorTime + scaledDelta
        guard result.isNumeric else {
            throw .timeOverflow
        }
        return result
    }
}
