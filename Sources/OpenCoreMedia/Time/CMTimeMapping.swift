public struct CMTimeMapping: Sendable {
  public var source: CMTimeRange
  public var target: CMTimeRange

  public init() {
    self = .invalid
  }

  public init(
    source: CMTimeRange,
    target: CMTimeRange
  ) {
    self.source = source
    self.target = target
  }

  public static let invalid = CMTimeMapping(
    source: .invalid,
    target: .invalid
  )

  public var isValid: Bool {
    target.isValid
  }

  public var isEmpty: Bool {
    !source.start.isNumeric && target.isValid
  }
}

// swift-format-ignore: AlwaysUseLowerCamelCase
public func CMTimeMappingMake(
  source: CMTimeRange,
  target: CMTimeRange
) -> CMTimeMapping {
  guard source.duration.epoch == 0,
    target.duration.epoch == 0
  else {
    return .invalid
  }

  return CMTimeMapping(
    source: source,
    target: target
  )
}

// swift-format-ignore: AlwaysUseLowerCamelCase
public func CMTimeMappingMakeEmpty(
  target: CMTimeRange
) -> CMTimeMapping {
  guard target.duration.epoch == 0 else {
    return .invalid
  }

  return CMTimeMapping(
    source: .invalid,
    target: target
  )
}
