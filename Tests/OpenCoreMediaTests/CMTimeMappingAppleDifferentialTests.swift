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
