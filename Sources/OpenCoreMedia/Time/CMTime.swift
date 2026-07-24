public struct CMTime: Sendable {
    public var value: CMTimeValue
    public var timescale: CMTimeScale
    public var flags: CMTimeFlags
    public var epoch: CMTimeEpoch

    public init() {
        self = .invalid
    }

    public init(value: CMTimeValue, timescale: CMTimeScale) {
        guard timescale > 0 else {
            self = .invalid
            return
        }

        self.init(
            value: value,
            timescale: timescale,
            flags: .valid,
            epoch: 0
        )
    }

    public init(
        value: CMTimeValue,
        timescale: CMTimeScale,
        flags: CMTimeFlags,
        epoch: CMTimeEpoch
    ) {
        self.value = value
        self.timescale = timescale
        self.flags = flags
        self.epoch = epoch
    }

    public static let zero = CMTime(
        value: 0,
        timescale: 1,
        flags: .valid,
        epoch: 0
    )

    public static let invalid = CMTime(
        value: 0,
        timescale: 0,
        flags: [],
        epoch: 0
    )

    public static let indefinite = CMTime(
        value: 0,
        timescale: 0,
        flags: [.valid, .indefinite],
        epoch: 0
    )

    public static let negativeInfinity = CMTime(
        value: 0,
        timescale: 0,
        flags: [.valid, .negativeInfinity],
        epoch: 0
    )

    public static let positiveInfinity = CMTime(
        value: 0,
        timescale: 0,
        flags: [.valid, .positiveInfinity],
        epoch: 0
    )

    public var isValid: Bool {
        flags.contains(.valid)
    }

    public var isNumeric: Bool {
        isValid && flags.intersection(.impliedValueFlagsMask).isEmpty
    }

    public var isIndefinite: Bool {
        isValid && flags.contains(.indefinite)
    }

    public var isPositiveInfinity: Bool {
        isValid && flags.contains(.positiveInfinity)
    }

    public var isNegativeInfinity: Bool {
        isValid && flags.contains(.negativeInfinity)
    }

    public var hasBeenRounded: Bool {
        flags.contains(.hasBeenRounded)
    }

    public var seconds: Double {
        if isPositiveInfinity {
            return .infinity
        }
        if isNegativeInfinity {
            return -.infinity
        }
        if isIndefinite || !isValid {
            return .nan
        }
        return Double(value) / Double(timescale)
    }

    public func convertScale(
        _ newTimescale: CMTimeScale,
        method: CMTimeRoundingMethod
    ) -> CMTime {
        guard isNumeric, timescale > 0, newTimescale > 0 else {
            return isNumeric ? .invalid : self
        }

        switch CMTimeArithmetic.scaledValue(
            value,
            from: timescale,
            to: newTimescale,
            method: method
        ) {
        case .success(let conversion):
            var resultFlags = flags
            if conversion.rounded {
                resultFlags.insert(.hasBeenRounded)
            }
            return CMTime(
                value: conversion.value,
                timescale: newTimescale,
                flags: resultFlags,
                epoch: epoch
            )
        case .positiveOverflow:
            return .positiveInfinity.withRoundedFlag(inheriting: flags)
        case .negativeOverflow:
            return .negativeInfinity.withRoundedFlag(inheriting: flags)
        }
    }

    public static func + (addend1: CMTime, addend2: CMTime) -> CMTime {
        CMTimeArithmetic.combine(addend1, addend2, operation: .add)
    }

    public static func - (minuend: CMTime, subtrahend: CMTime) -> CMTime {
        CMTimeArithmetic.combine(minuend, subtrahend, operation: .subtract)
    }

    private func withRoundedFlag(inheriting sourceFlags: CMTimeFlags) -> CMTime {
        var result = self
        if sourceFlags.contains(.hasBeenRounded) {
            result.flags.insert(.hasBeenRounded)
        }
        result.flags.insert(.hasBeenRounded)
        return result
    }
}

extension CMTime: Comparable {
    public static func == (lhs: CMTime, rhs: CMTime) -> Bool {
        CMTimeArithmetic.compare(lhs, rhs) == 0
    }

    public static func < (lhs: CMTime, rhs: CMTime) -> Bool {
        CMTimeArithmetic.compare(lhs, rhs) < 0
    }
}

extension CMTime: Hashable {
    public func hash(into hasher: inout Hasher) {
        let rank = CMTimeArithmetic.rank(of: self)
        hasher.combine(rank)

        guard rank == CMTimeArithmetic.numericRank, timescale > 0 else {
            hasher.combine(value)
            hasher.combine(timescale)
            hasher.combine(epoch)
            return
        }

        let divisor = CMTimeArithmetic.greatestCommonDivisor(
            value.magnitude,
            UInt64(timescale)
        )
        hasher.combine(value / Int64(divisor))
        hasher.combine(Int64(timescale) / Int64(divisor))
        hasher.combine(epoch)
    }
}

public func CMTimeCompare(_ time1: CMTime, _ time2: CMTime) -> Int32 {
    CMTimeArithmetic.compare(time1, time2)
}
