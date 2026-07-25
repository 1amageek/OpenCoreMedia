enum CMTimeArithmetic {
  static let numericRank: UInt8 = 1
  private static let maximumArithmeticTimescale: CMTimeScale = 1_000_000_000

  enum Operation {
    case add
    case subtract
  }

  struct Conversion {
    let value: Int64
    let rounded: Bool
  }

  enum ConversionResult {
    case success(Conversion)
    case positiveOverflow
    case negativeOverflow
  }

  static func combine(
    _ lhs: CMTime,
    _ rhs: CMTime,
    operation: Operation
  ) -> CMTime {
    guard lhs.isValid, rhs.isValid else {
      return .invalid
    }

    if let special = specialResult(lhs, rhs, operation: operation) {
      return special
    }

    guard lhs.isNumeric, rhs.isNumeric,
      lhs.timescale > 0, rhs.timescale > 0
    else {
      return .invalid
    }

    guard lhs.epoch == 0 || rhs.epoch == 0 || lhs.epoch == rhs.epoch else {
      return .invalid
    }

    let resultEpoch: CMTimeEpoch
    if lhs.epoch != 0, rhs.epoch != 0 {
      resultEpoch = 0
    } else {
      resultEpoch = lhs.epoch == 0 ? rhs.epoch : lhs.epoch
    }
    let commonScale = commonTimescale(lhs.timescale, rhs.timescale)
    var targetScale = commonScale.scale
    var rounded = commonScale.wasClamped

    while true {
      let left = scaledValue(
        lhs.value,
        from: lhs.timescale,
        to: targetScale,
        method: .default
      )
      let right = scaledValue(
        rhs.value,
        from: rhs.timescale,
        to: targetScale,
        method: .default
      )

      if case .success(let leftValue) = left,
        case .success(let rightValue) = right
      {
        let result: (partialValue: Int64, overflow: Bool)
        switch operation {
        case .add:
          result = leftValue.value.addingReportingOverflow(
            rightValue.value
          )
        case .subtract:
          result = leftValue.value.subtractingReportingOverflow(
            rightValue.value
          )
        }

        if !result.overflow {
          var flags: CMTimeFlags = .valid
          if rounded
            || leftValue.rounded
            || rightValue.rounded
            || lhs.hasBeenRounded
            || rhs.hasBeenRounded
          {
            flags.insert(.hasBeenRounded)
          }
          return CMTime(
            value: result.partialValue,
            timescale: targetScale,
            flags: flags,
            epoch: resultEpoch
          )
        }
      }

      guard targetScale > 1 else {
        return overflowResult(lhs, rhs, operation: operation)
      }
      targetScale = max(1, targetScale / 2)
      rounded = true
    }
  }

  static func compare(_ lhs: CMTime, _ rhs: CMTime) -> Int32 {
    let leftRank = rank(of: lhs)
    let rightRank = rank(of: rhs)
    if leftRank != rightRank {
      return leftRank < rightRank ? -1 : 1
    }

    guard leftRank == numericRank else {
      return 0
    }

    if lhs.epoch != rhs.epoch {
      return lhs.epoch < rhs.epoch ? -1 : 1
    }

    guard lhs.timescale > 0, rhs.timescale > 0 else {
      if lhs.timescale == rhs.timescale && lhs.value == rhs.value {
        return 0
      }
      if lhs.timescale != rhs.timescale {
        return lhs.timescale < rhs.timescale ? -1 : 1
      }
      return lhs.value < rhs.value ? -1 : 1
    }

    let leftProduct = lhs.value.multipliedFullWidth(
      by: Int64(rhs.timescale)
    )
    let rightProduct = rhs.value.multipliedFullWidth(
      by: Int64(lhs.timescale)
    )

    if leftProduct.high != rightProduct.high {
      return leftProduct.high < rightProduct.high ? -1 : 1
    }
    if leftProduct.low != rightProduct.low {
      return leftProduct.low < rightProduct.low ? -1 : 1
    }
    return 0
  }

  static func rank(of time: CMTime) -> UInt8 {
    if !time.isValid {
      return 4
    }
    if time.isNegativeInfinity {
      return 0
    }
    if time.isPositiveInfinity {
      return 3
    }
    if time.isIndefinite {
      return 2
    }
    return numericRank
  }

  static func greatestCommonDivisor(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
    var a = lhs
    var b = rhs
    while b != 0 {
      let remainder = a % b
      a = b
      b = remainder
    }
    return a == 0 ? 1 : a
  }

  static func scaledValue(
    _ value: Int64,
    from sourceScale: Int32,
    to targetScale: Int32,
    method: CMTimeRoundingMethod
  ) -> ConversionResult {
    guard sourceScale > 0, targetScale > 0 else {
      return value < 0 ? .negativeOverflow : .positiveOverflow
    }

    let denominator = Int64(sourceScale)
    let multiplier = Int64(targetScale)
    let quotient = value / denominator
    let sourceRemainder = value % denominator

    let whole = quotient.multipliedReportingOverflow(by: multiplier)
    if whole.overflow {
      return value < 0 ? .negativeOverflow : .positiveOverflow
    }

    let fractionalProduct = sourceRemainder.multipliedReportingOverflow(
      by: multiplier
    )
    if fractionalProduct.overflow {
      return value < 0 ? .negativeOverflow : .positiveOverflow
    }

    let fractionalValue = fractionalProduct.partialValue / denominator
    let fractionalRemainder = fractionalProduct.partialValue % denominator
    let combined = whole.partialValue.addingReportingOverflow(fractionalValue)
    if combined.overflow {
      return value < 0 ? .negativeOverflow : .positiveOverflow
    }

    guard fractionalRemainder != 0 else {
      return .success(Conversion(value: combined.partialValue, rounded: false))
    }

    let effectiveMethod: CMTimeRoundingMethod
    if method == .quickTime {
      effectiveMethod =
        targetScale < sourceScale
        ? .roundTowardZero
        : .roundAwayFromZero
    } else {
      effectiveMethod = method
    }

    let adjustment: Int64
    switch effectiveMethod {
    case .roundTowardZero:
      adjustment = 0
    case .roundAwayFromZero:
      adjustment = fractionalRemainder < 0 ? -1 : 1
    case .roundHalfAwayFromZero:
      adjustment =
        fractionalRemainder.magnitude * 2
          >= UInt64(denominator)
        ? (fractionalRemainder < 0 ? -1 : 1)
        : 0
    case .roundTowardPositiveInfinity:
      adjustment = fractionalRemainder > 0 ? 1 : 0
    case .roundTowardNegativeInfinity:
      adjustment = fractionalRemainder < 0 ? -1 : 0
    case .quickTime:
      adjustment = 0
    }

    let adjusted = combined.partialValue.addingReportingOverflow(adjustment)
    if adjusted.overflow {
      return adjustment < 0 ? .negativeOverflow : .positiveOverflow
    }
    return .success(Conversion(value: adjusted.partialValue, rounded: true))
  }

  static func commonTimescale(
    _ lhs: Int32,
    _ rhs: Int32
  ) -> (scale: Int32, wasClamped: Bool) {
    if lhs == rhs {
      return (lhs, false)
    }

    let divisor = greatestCommonDivisor(UInt64(lhs), UInt64(rhs))
    let product = (Int64(lhs) / Int64(divisor)) * Int64(rhs)
    if product > Int64(maximumArithmeticTimescale) {
      return (maximumArithmeticTimescale, true)
    }
    return (Int32(product), false)
  }

  static func scaledDuration(
    _ duration: CMTime,
    from sourceDuration: CMTime,
    to targetDuration: CMTime
  ) -> CMTime {
    let rawNumeratorFirst =
      Int128(duration.value).multipliedReportingOverflow(
        by: Int128(targetDuration.value)
      )
    let rawNumerator =
      rawNumeratorFirst.partialValue
      .multipliedReportingOverflow(
        by: Int128(sourceDuration.timescale)
      )
    let rawDenominator =
      Int128(targetDuration.timescale)
      * Int128(sourceDuration.value)
    guard !rawNumeratorFirst.overflow,
      !rawNumerator.overflow,
      rawDenominator != 0
    else {
      return overflowResult(
        numerator: rawNumerator.partialValue,
        inheriting: duration.flags
      )
    }

    let rawValue =
      rawNumerator.partialValue / rawDenominator
    let rawRemainder =
      rawNumerator.partialValue % rawDenominator
    if rawRemainder == 0,
      rawValue >= Int128(Int64.min),
      rawValue <= Int128(Int64.max)
    {
      return CMTime(
        value: Int64(rawValue),
        timescale: duration.timescale,
        flags: duration.flags,
        epoch: duration.epoch
      )
    }

    let denominatorFirst =
      Int128(duration.timescale)
      .multipliedReportingOverflow(
        by: Int128(targetDuration.timescale)
      )
    let denominator =
      denominatorFirst.partialValue
      .multipliedReportingOverflow(
        by: Int128(sourceDuration.value)
      )
    guard !denominatorFirst.overflow,
      !denominator.overflow,
      denominator.partialValue != 0
    else {
      return overflowResult(
        numerator: rawNumerator.partialValue,
        inheriting: duration.flags
      )
    }

    let preferredTimescale: CMTimeScale = 1_000_000_000
    let preferredNumerator =
      rawNumerator.partialValue
      .multipliedReportingOverflow(
        by: Int128(preferredTimescale)
      )
    guard !preferredNumerator.overflow else {
      return overflowResult(
        numerator: rawNumerator.partialValue,
        inheriting: duration.flags
      )
    }

    let preferredValue = roundedQuotient(
      preferredNumerator.partialValue,
      denominator.partialValue
    )
    guard preferredValue >= Int128(Int64.min),
      preferredValue <= Int128(Int64.max)
    else {
      return overflowResult(
        numerator: preferredValue,
        inheriting: duration.flags
      )
    }

    var flags = duration.flags
    if duration != sourceDuration {
      flags.insert(.hasBeenRounded)
    }
    return CMTime(
      value: Int64(preferredValue),
      timescale: preferredTimescale,
      flags: flags,
      epoch: duration.epoch
    )
  }

  static func mappedTime(
    _ time: CMTime,
    from sourceRange: CMTimeRange,
    to targetRange: CMTimeRange
  ) -> CMTime {
    let offset = time - sourceRange.start
    guard offset.isNumeric else {
      return .invalid
    }

    let mappedNumeratorFirst =
      Int128(offset.value).multipliedReportingOverflow(
        by: Int128(targetRange.duration.value)
      )
    let mappedNumerator =
      mappedNumeratorFirst.partialValue
      .multipliedReportingOverflow(
        by: Int128(sourceRange.duration.timescale)
      )
    let mappedDenominatorFirst =
      Int128(offset.timescale).multipliedReportingOverflow(
        by: Int128(targetRange.duration.timescale)
      )
    let mappedDenominator =
      mappedDenominatorFirst.partialValue
      .multipliedReportingOverflow(
        by: Int128(sourceRange.duration.value)
      )
    guard !mappedNumeratorFirst.overflow,
      !mappedNumerator.overflow,
      !mappedDenominatorFirst.overflow,
      !mappedDenominator.overflow,
      mappedDenominator.partialValue != 0
    else {
      return .invalid
    }

    let mappedAtTargetScale =
      mappedNumerator.partialValue
      .multipliedReportingOverflow(
        by: Int128(targetRange.start.timescale)
      )
    let targetNumerator =
      Int128(targetRange.start.value)
      .multipliedReportingOverflow(
        by: mappedDenominator.partialValue
      )
    guard !mappedAtTargetScale.overflow,
      !targetNumerator.overflow
    else {
      return .invalid
    }

    let combinedNumerator =
      mappedAtTargetScale.partialValue
      .addingReportingOverflow(
        targetNumerator.partialValue
      )
    let combinedDenominator =
      mappedDenominator.partialValue
      .multipliedReportingOverflow(
        by: Int128(targetRange.start.timescale)
      )
    guard !combinedNumerator.overflow,
      !combinedDenominator.overflow,
      combinedDenominator.partialValue != 0
    else {
      return .invalid
    }

    let preferredTimescale: CMTimeScale = 1_000_000_000
    let preferredNumerator =
      combinedNumerator.partialValue
      .multipliedReportingOverflow(
        by: Int128(preferredTimescale)
      )
    guard !preferredNumerator.overflow else {
      return .invalid
    }

    let value =
      preferredNumerator.partialValue
      / combinedDenominator.partialValue
    guard value >= Int128(Int64.min),
      value <= Int128(Int64.max)
    else {
      return overflowResult(
        numerator: value,
        inheriting: time.flags
      )
    }

    var flags: CMTimeFlags = .valid
    if time.hasBeenRounded
      || sourceRange.start.hasBeenRounded
      || sourceRange.duration.hasBeenRounded
      || targetRange.start.hasBeenRounded
      || targetRange.duration.hasBeenRounded
      || preferredNumerator.partialValue
        % combinedDenominator.partialValue != 0
    {
      flags.insert(.hasBeenRounded)
    }
    return CMTime(
      value: Int64(value),
      timescale: preferredTimescale,
      flags: flags,
      epoch: targetRange.start.epoch
    )
  }

  private static func roundedQuotient(
    _ numerator: Int128,
    _ denominator: Int128
  ) -> Int128 {
    let quotient = numerator / denominator
    let remainder = numerator % denominator
    guard remainder != 0,
      remainder.magnitude * 2
        >= denominator.magnitude
    else {
      return quotient
    }

    let sameSign =
      (numerator < 0) == (denominator < 0)
    return quotient + (sameSign ? 1 : -1)
  }

  private static func specialResult(
    _ lhs: CMTime,
    _ rhs: CMTime,
    operation: Operation
  ) -> CMTime? {
    let rhsPositive: Bool
    let rhsNegative: Bool
    switch operation {
    case .add:
      rhsPositive = rhs.isPositiveInfinity
      rhsNegative = rhs.isNegativeInfinity
    case .subtract:
      rhsPositive = rhs.isNegativeInfinity
      rhsNegative = rhs.isPositiveInfinity
    }

    if lhs.isPositiveInfinity {
      return rhsNegative ? .invalid : .positiveInfinity
    }
    if lhs.isNegativeInfinity {
      return rhsPositive ? .invalid : .negativeInfinity
    }
    if rhsPositive {
      return .positiveInfinity
    }
    if rhsNegative {
      return .negativeInfinity
    }
    if lhs.isIndefinite || rhs.isIndefinite {
      return .indefinite
    }
    return nil
  }

  private static func overflowResult(
    _ lhs: CMTime,
    _ rhs: CMTime,
    operation: Operation
  ) -> CMTime {
    let positive: Bool
    switch operation {
    case .add:
      positive = lhs.value >= 0 && rhs.value >= 0
    case .subtract:
      positive = lhs.value >= 0 && rhs.value < 0
    }
    return positive ? CMTime.positiveInfinity : CMTime.negativeInfinity
  }

  private static func signedInfinity(
    negative: Bool,
    inheriting sourceFlags: CMTimeFlags
  ) -> CMTime {
    var result =
      negative
      ? CMTime.negativeInfinity
      : CMTime.positiveInfinity
    if sourceFlags.contains(.hasBeenRounded) {
      result.flags.insert(.hasBeenRounded)
    }
    return result
  }

  private static func overflowResult(
    numerator: Int128,
    inheriting sourceFlags: CMTimeFlags
  ) -> CMTime {
    var result = signedInfinity(
      negative: numerator < 0,
      inheriting: sourceFlags
    )
    result.flags.insert(.hasBeenRounded)
    return result
  }
}
