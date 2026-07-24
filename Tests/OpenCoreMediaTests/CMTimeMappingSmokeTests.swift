import OpenCoreMedia
import Testing

@Suite("CMTime mapping smoke")
struct CMTimeMappingSmokeTests {
  @Test("Mapping construction distinguishes raw initialization and factories")
  func construction() {
    let source = CMTimeRange(
      start: CMTime(value: 1, timescale: 1),
      duration: CMTime(value: 2, timescale: 1)
    )
    let target = CMTimeRange(
      start: CMTime(value: 10, timescale: 1),
      duration: CMTime(value: 4, timescale: 1)
    )

    let mapping = CMTimeMapping(
      source: source,
      target: target
    )
    #expect(mapping.source == source)
    #expect(mapping.target == target)
    #expect(mapping.isValid)
    #expect(mapping.isEmpty == false)

    #expect(CMTimeMapping().isValid == false)
    #expect(CMTimeMapping.invalid.isValid == false)

    let empty = CMTimeMappingMakeEmpty(target: target)
    #expect(empty.isValid)
    #expect(empty.isEmpty)
    #expect(empty.source == .invalid)
    #expect(empty.target == target)
  }

  @Test("Mapping factories validate duration epochs")
  func factoryValidation() {
    let validRange = CMTimeRange(
      start: .zero,
      duration: CMTime(value: 1, timescale: 1)
    )
    let durationWithEpoch = CMTime(
      value: 1,
      timescale: 1,
      flags: .valid,
      epoch: 1
    )
    let invalidDurationRange = CMTimeRange(
      start: .zero,
      duration: durationWithEpoch
    )

    #expect(
      CMTimeMappingMake(
        source: invalidDurationRange,
        target: validRange
      ).isValid == false
    )
    #expect(
      CMTimeMappingMakeEmpty(
        target: invalidDurationRange
      ).isValid == false
    )

    let raw = CMTimeMapping(
      source: invalidDurationRange,
      target: validRange
    )
    #expect(raw.source == invalidDurationRange)
    #expect(raw.target == validRange)
    #expect(raw.isValid)
  }

  @Test("Time and duration map linearly while preserving endpoints")
  func linearMapping() {
    let source = CMTimeRange(
      start: CMTime(value: 1, timescale: 1),
      duration: CMTime(value: 2, timescale: 1)
    )
    let target = CMTimeRange(
      start: CMTime(value: 10, timescale: 1),
      duration: CMTime(value: 4, timescale: 1)
    )

    #expect(
      CMTimeMapTimeFromRangeToRange(
        source.start,
        fromRange: source,
        toRange: target
      ) == target.start
    )
    #expect(
      CMTimeMapTimeFromRangeToRange(
        CMTime(value: 2, timescale: 1),
        fromRange: source,
        toRange: target
      ) == CMTime(value: 12, timescale: 1)
    )
    #expect(
      CMTimeMapTimeFromRangeToRange(
        source.end,
        fromRange: source,
        toRange: target
      ) == target.end
    )
    #expect(
      CMTimeMapDurationFromRangeToRange(
        CMTime(value: 1, timescale: 1),
        fromRange: source,
        toRange: target
      ) == CMTime(value: 2, timescale: 1)
    )
  }

  @Test("Nonintegral mapping follows Core Media nanosecond rounding")
  func nonintegralMapping() {
    let source = CMTimeRange(
      start: CMTime(value: 1, timescale: 7),
      duration: CMTime(value: 2, timescale: 5)
    )
    let target = CMTimeRange(
      start: CMTime(value: 3, timescale: 13),
      duration: CMTime(value: 7, timescale: 11)
    )

    let duration = CMTimeMapDurationFromRangeToRange(
      CMTime(value: 1, timescale: 3),
      fromRange: source,
      toRange: target
    )
    #expect(duration.value == 530_303_030)
    #expect(duration.timescale == 1_000_000_000)
    #expect(duration.hasBeenRounded)
  }

  @Test("Mapping rejects empty ranges and epoch mismatches")
  func invalidMapping() {
    let target = CMTimeRange(
      start: .zero,
      duration: CMTime(value: 1, timescale: 1)
    )
    #expect(
      CMTimeMapTimeFromRangeToRange(
        .zero,
        fromRange: .zero,
        toRange: target
      ) == .invalid
    )

    let epochTime = CMTime(
      value: 1,
      timescale: 1,
      flags: .valid,
      epoch: 1
    )
    #expect(
      CMTimeMapTimeFromRangeToRange(
        epochTime,
        fromRange: target,
        toRange: target
      ) == .invalid
    )
    #expect(
      CMTimeMapDurationFromRangeToRange(
        epochTime,
        fromRange: target,
        toRange: target
      ) == .invalid
    )
  }

  @Test("Clamp and fold preserve exact rational values")
  func clampAndFold() {
    let range = CMTimeRange(
      start: CMTime(value: 1, timescale: 3),
      duration: CMTime(value: 2, timescale: 5)
    )

    #expect(
      CMTimeClampToRange(
        .zero,
        range: range
      ) == range.start
    )
    #expect(
      CMTimeClampToRange(
        CMTime(value: 2, timescale: 1),
        range: range
      ) == range.end
    )
    #expect(
      CMTimeFoldIntoRange(
        .zero,
        foldRange: range
      ) == CMTime(value: 6, timescale: 15)
    )
    #expect(
      CMTimeFoldIntoRange(
        CMTime(value: -7, timescale: 11),
        foldRange: range
      ) == CMTime(value: 93, timescale: 165)
    )
  }

  @Test("Infinite ranges only map when both durations are infinite")
  func infiniteMapping() {
    let source = CMTimeRange(
      start: CMTime(value: 1, timescale: 1),
      duration: .positiveInfinity
    )
    let target = CMTimeRange(
      start: CMTime(value: 10, timescale: 1),
      duration: .positiveInfinity
    )

    #expect(
      CMTimeMapTimeFromRangeToRange(
        CMTime(value: 5, timescale: 1),
        fromRange: source,
        toRange: target
      ) == CMTime(value: 14, timescale: 1)
    )
    #expect(
      CMTimeMapDurationFromRangeToRange(
        CMTime(value: 3, timescale: 2),
        fromRange: source,
        toRange: target
      ) == CMTime(value: 3, timescale: 2)
    )
  }
}
