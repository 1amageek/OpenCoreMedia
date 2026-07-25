#if canImport(CoreMedia)
  import CoreMedia
  import OpenCoreMedia
  import Testing

  @Suite("CMTime mapping Apple differential")
  struct CMTimeMappingAppleDifferentialTests {
    @Test("Portable mapping matches Apple Core Media fixtures")
    func mappingFixtures() {
      let openSource = OpenCoreMedia.CMTimeRange(
        start: OpenCoreMedia.CMTime(
          value: 1,
          timescale: 7
        ),
        duration: OpenCoreMedia.CMTime(
          value: 2,
          timescale: 5
        )
      )
      let openTarget = OpenCoreMedia.CMTimeRange(
        start: OpenCoreMedia.CMTime(
          value: 3,
          timescale: 13
        ),
        duration: OpenCoreMedia.CMTime(
          value: 7,
          timescale: 11
        )
      )
      let appleSource = CoreMedia.CMTimeRange(
        start: CoreMedia.CMTime(
          value: 1,
          timescale: 7
        ),
        duration: CoreMedia.CMTime(
          value: 2,
          timescale: 5
        )
      )
      let appleTarget = CoreMedia.CMTimeRange(
        start: CoreMedia.CMTime(
          value: 3,
          timescale: 13
        ),
        duration: CoreMedia.CMTime(
          value: 7,
          timescale: 11
        )
      )

      let openDuration =
        OpenCoreMedia.CMTimeMapDurationFromRangeToRange(
          OpenCoreMedia.CMTime(
            value: 1,
            timescale: 3
          ),
          fromRange: openSource,
          toRange: openTarget
        )
      let appleDuration =
        CoreMedia.CMTimeMapDurationFromRangeToRange(
          CoreMedia.CMTime(
            value: 1,
            timescale: 3
          ),
          fromRange: appleSource,
          toRange: appleTarget
        )
      expectEqual(openDuration, appleDuration)

      let openMapped =
        OpenCoreMedia.CMTimeMapTimeFromRangeToRange(
          OpenCoreMedia.CMTime(
            value: 12,
            timescale: 7
          ),
          fromRange: openSource,
          toRange: openTarget
        )
      let appleMapped =
        CoreMedia.CMTimeMapTimeFromRangeToRange(
          CoreMedia.CMTime(
            value: 12,
            timescale: 7
          ),
          fromRange: appleSource,
          toRange: appleTarget
        )
      expectEqual(openMapped, appleMapped)
    }

    @Test("Portable fold matches Apple Core Media fixtures")
    func foldFixtures() {
      let openRange = OpenCoreMedia.CMTimeRange(
        start: OpenCoreMedia.CMTime(
          value: 1,
          timescale: 3
        ),
        duration: OpenCoreMedia.CMTime(
          value: 2,
          timescale: 5
        )
      )
      let appleRange = CoreMedia.CMTimeRange(
        start: CoreMedia.CMTime(
          value: 1,
          timescale: 3
        ),
        duration: CoreMedia.CMTime(
          value: 2,
          timescale: 5
        )
      )

      let fixtures: [(Int64, Int32)] = [
        (0, 1),
        (1, 2),
        (7, 3),
        (-7, 11),
      ]
      for fixture in fixtures {
        let openResult =
          OpenCoreMedia.CMTimeFoldIntoRange(
            OpenCoreMedia.CMTime(
              value: fixture.0,
              timescale: fixture.1
            ),
            foldRange: openRange
          )
        let appleResult =
          CoreMedia.CMTimeFoldIntoRange(
            CoreMedia.CMTime(
              value: fixture.0,
              timescale: fixture.1
            ),
            foldRange: appleRange
          )
        expectEqual(openResult, appleResult)
      }
    }

    @Test("Portable arithmetic matches Apple overflow fixtures")
    func overflowFixtures() {
      let fixtures: [
        (
          OpenCoreMedia.CMTime,
          OpenCoreMedia.CMTime,
          CoreMedia.CMTime,
          CoreMedia.CMTime
        )
      ] = [
        (
          OpenCoreMedia.CMTime(value: .max, timescale: 1),
          OpenCoreMedia.CMTime(value: .max, timescale: 1),
          CoreMedia.CMTime(value: .max, timescale: 1),
          CoreMedia.CMTime(value: .max, timescale: 1)
        ),
        (
          OpenCoreMedia.CMTime(value: .min, timescale: 1),
          OpenCoreMedia.CMTime(value: .min, timescale: 1),
          CoreMedia.CMTime(value: .min, timescale: 1),
          CoreMedia.CMTime(value: .min, timescale: 1)
        ),
        (
          OpenCoreMedia.CMTime(value: .max, timescale: 2),
          OpenCoreMedia.CMTime(value: .max, timescale: 3),
          CoreMedia.CMTime(value: .max, timescale: 2),
          CoreMedia.CMTime(value: .max, timescale: 3)
        ),
        (
          OpenCoreMedia.CMTime(value: .max, timescale: .max),
          OpenCoreMedia.CMTime(value: .max - 1, timescale: .max - 1),
          CoreMedia.CMTime(value: .max, timescale: .max),
          CoreMedia.CMTime(value: .max - 1, timescale: .max - 1)
        ),
      ]

      for fixture in fixtures {
        expectEqual(fixture.0 + fixture.1, CMTimeAdd(fixture.2, fixture.3))
        expectEqual(fixture.0 - fixture.1, CMTimeSubtract(fixture.2, fixture.3))
      }

      let openConverted = OpenCoreMedia.CMTime(
        value: .max,
        timescale: 1,
        flags: [.valid, .hasBeenRounded],
        epoch: 0
      ).convertScale(.max, method: .default)
      let appleConverted = CMTimeConvertScale(
        CoreMedia.CMTime(
          value: .max,
          timescale: 1,
          flags: [.valid, .hasBeenRounded],
          epoch: 0
        ),
        timescale: .max,
        method: .default
      )
      expectEqual(openConverted, appleConverted)
    }

    @Test("Portable arithmetic matches Apple epoch fixtures")
    func epochFixtures() {
      let openDuration = OpenCoreMedia.CMTime(value: 1, timescale: 1)
      let appleDuration = CoreMedia.CMTime(value: 1, timescale: 1)
      let openEpochThree = OpenCoreMedia.CMTime(
        value: 2,
        timescale: 1,
        flags: .valid,
        epoch: 3
      )
      let appleEpochThree = CoreMedia.CMTime(
        value: 2,
        timescale: 1,
        flags: .valid,
        epoch: 3
      )
      let openSameEpoch = OpenCoreMedia.CMTime(
        value: 4,
        timescale: 1,
        flags: .valid,
        epoch: 3
      )
      let appleSameEpoch = CoreMedia.CMTime(
        value: 4,
        timescale: 1,
        flags: .valid,
        epoch: 3
      )
      let openOtherEpoch = OpenCoreMedia.CMTime(
        value: 4,
        timescale: 1,
        flags: .valid,
        epoch: 4
      )
      let appleOtherEpoch = CoreMedia.CMTime(
        value: 4,
        timescale: 1,
        flags: .valid,
        epoch: 4
      )

      expectEqual(
        openEpochThree + openDuration,
        CMTimeAdd(appleEpochThree, appleDuration)
      )
      expectEqual(
        openEpochThree + openSameEpoch,
        CMTimeAdd(appleEpochThree, appleSameEpoch)
      )
      expectEqual(
        openEpochThree - openSameEpoch,
        CMTimeSubtract(appleEpochThree, appleSameEpoch)
      )
      expectEqual(
        openEpochThree + openOtherEpoch,
        CMTimeAdd(appleEpochThree, appleOtherEpoch)
      )
      expectEqual(
        openEpochThree - openOtherEpoch,
        CMTimeSubtract(appleEpochThree, appleOtherEpoch)
      )
      #expect(
        OpenCoreMedia.CMTimeCompare(openEpochThree, openOtherEpoch)
          == CoreMedia.CMTimeCompare(appleEpochThree, appleOtherEpoch)
      )
    }

    private func expectEqual(
      _ open: OpenCoreMedia.CMTime,
      _ apple: CoreMedia.CMTime
    ) {
      #expect(open.value == apple.value)
      #expect(open.timescale == apple.timescale)
      #expect(open.flags.rawValue == apple.flags.rawValue)
      #expect(open.epoch == apple.epoch)
    }
  }
#endif
