public struct CMTimeRange: Sendable, Hashable {
    public var start: CMTime
    public var duration: CMTime

    public init() {
        self = .zero
    }

    public init(start: CMTime, duration: CMTime) {
        self.start = start
        self.duration = duration
    }

    public init(start: CMTime, end: CMTime) {
        guard start.isValid,
              end.isValid,
              start.epoch == end.epoch,
              start <= end
        else {
            self = .invalid
            return
        }

        let duration = end - start
        guard duration.isValid else {
            self = .invalid
            return
        }

        self.init(start: start, duration: duration)
    }

    public static let zero = CMTimeRange(
        start: .zero,
        duration: .zero
    )

    public static let invalid = CMTimeRange(
        start: .invalid,
        duration: .invalid
    )

    public var isValid: Bool {
        start.isValid
            && duration.isValid
            && duration.epoch == 0
            && duration.value >= 0
    }

    public var isEmpty: Bool {
        isValid && duration == .zero
    }

    public var isIndefinite: Bool {
        isValid && (start.isIndefinite || duration.isIndefinite)
    }

    public var end: CMTime {
        start + duration
    }

    public func containsTime(_ time: CMTime) -> Bool {
        guard isValid,
              !isEmpty,
              !isIndefinite,
              time.isValid,
              time.epoch == start.epoch
        else {
            return false
        }

        return start <= time && time < end
    }

    public func containsTimeRange(_ range: CMTimeRange) -> Bool {
        guard isValid,
              range.isValid,
              !isIndefinite,
              !range.isIndefinite,
              range.start.epoch == start.epoch
        else {
            return false
        }

        if range.isEmpty {
            return containsTime(range.start)
        }

        return start <= range.start && range.end <= end
    }

    public func intersection(_ otherRange: CMTimeRange) -> CMTimeRange {
        guard canCombine(with: otherRange) else {
            return .invalid
        }

        let intersectionStart = max(start, otherRange.start)
        let intersectionEnd = min(end, otherRange.end)
        guard intersectionStart < intersectionEnd else {
            return .zero
        }

        return CMTimeRange(
            start: intersectionStart,
            end: intersectionEnd
        )
    }

    public func union(_ otherRange: CMTimeRange) -> CMTimeRange {
        guard canCombine(with: otherRange) else {
            return .invalid
        }

        return CMTimeRange(
            start: min(start, otherRange.start),
            end: max(end, otherRange.end)
        )
    }

    private func canCombine(with otherRange: CMTimeRange) -> Bool {
        isValid
            && otherRange.isValid
            && !isIndefinite
            && !otherRange.isIndefinite
            && start.epoch == otherRange.start.epoch
    }
}
