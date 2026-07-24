// swift-format-ignore: AlwaysUseLowerCamelCase
public func CMTimeClampToRange(
  _ time: CMTime,
  range: CMTimeRange
) -> CMTime {
  guard time.isValid,
    range.isValid,
    !range.isEmpty
  else {
    return .invalid
  }

  if time < range.start {
    return range.start
  }
  if time > range.end {
    return range.end
  }
  return time
}

// swift-format-ignore: AlwaysUseLowerCamelCase
public func CMTimeMapTimeFromRangeToRange(
  _ time: CMTime,
  fromRange: CMTimeRange,
  toRange: CMTimeRange
) -> CMTime {
  guard time.isValid,
    fromRange.isValid,
    toRange.isValid,
    !fromRange.isEmpty,
    !toRange.isEmpty,
    time.epoch == fromRange.start.epoch
  else {
    return .invalid
  }

  if time == fromRange.start {
    return toRange.start
  }
  if time == fromRange.end {
    return toRange.end
  }

  if fromRange.duration.isPositiveInfinity,
    toRange.duration.isPositiveInfinity
  {
    return time - fromRange.start + toRange.start
  }

  let offset = time - fromRange.start
  let mappedOffset = CMTimeMapDurationFromRangeToRange(
    offset,
    fromRange: fromRange,
    toRange: toRange
  )
  guard mappedOffset.isValid else {
    return .invalid
  }
  if mappedOffset.timescale == 1_000_000_000 {
    return CMTimeArithmetic.mappedTime(
      time,
      from: fromRange,
      to: toRange
    )
  }
  let mappedStart = toRange.start.convertScale(
    mappedOffset.timescale,
    method: .default
  )
  guard mappedStart.isValid else {
    return .invalid
  }
  return mappedOffset + mappedStart
}

// swift-format-ignore: AlwaysUseLowerCamelCase
public func CMTimeMapDurationFromRangeToRange(
  _ duration: CMTime,
  fromRange: CMTimeRange,
  toRange: CMTimeRange
) -> CMTime {
  guard duration.isNumeric,
    duration.epoch == 0,
    fromRange.isValid,
    toRange.isValid,
    !fromRange.isEmpty,
    !toRange.isEmpty
  else {
    return .invalid
  }

  if fromRange.duration.isPositiveInfinity,
    toRange.duration.isPositiveInfinity
  {
    return duration
  }

  guard fromRange.duration.isNumeric,
    toRange.duration.isNumeric,
    fromRange.duration.value > 0,
    toRange.duration.value > 0
  else {
    return .invalid
  }

  return CMTimeArithmetic.scaledDuration(
    duration,
    from: fromRange.duration,
    to: toRange.duration
  )
}

// swift-format-ignore: AlwaysUseLowerCamelCase
public func CMTimeFoldIntoRange(
  _ time: CMTime,
  foldRange: CMTimeRange
) -> CMTime {
  guard time.isNumeric,
    foldRange.isValid,
    !foldRange.isEmpty,
    !foldRange.isIndefinite,
    foldRange.duration.isNumeric,
    foldRange.duration.value > 0,
    time.epoch == foldRange.start.epoch
  else {
    return .invalid
  }

  let offset = time - foldRange.start
  guard offset.isNumeric else {
    return .invalid
  }

  let commonScale = CMTimeArithmetic.commonTimescale(
    offset.timescale,
    foldRange.duration.timescale
  )
  let scaledOffset = offset.convertScale(
    commonScale.scale,
    method: .default
  )
  let scaledDuration = foldRange.duration.convertScale(
    commonScale.scale,
    method: .default
  )
  guard scaledOffset.isNumeric,
    scaledDuration.isNumeric,
    scaledDuration.value > 0
  else {
    return .invalid
  }

  var remainder =
    scaledOffset.value % scaledDuration.value
  if remainder < 0 {
    remainder += scaledDuration.value
  }
  if remainder == 0 {
    return foldRange.start
  }

  var flags: CMTimeFlags = .valid
  if commonScale.wasClamped
    || scaledOffset.hasBeenRounded
    || scaledDuration.hasBeenRounded
  {
    flags.insert(.hasBeenRounded)
  }

  let foldedOffset = CMTime(
    value: remainder,
    timescale: commonScale.scale,
    flags: flags,
    epoch: 0
  )
  return foldRange.start + foldedOffset
}
