import OpenCoreMedia
import Testing

@Suite("CMTimeRange smoke")
struct CMTimeRangeSmokeTests {
    @Test("Construction exposes start duration end and predicates")
    func construction() {
        let start = CMTime(value: 1, timescale: 2)
        let duration = CMTime(value: 3, timescale: 2)
        let range = CMTimeRange(start: start, duration: duration)

        #expect(range.start == start)
        #expect(range.duration == duration)
        #expect(range.end == CMTime(value: 2, timescale: 1))
        #expect(range.isValid)
        #expect(range.isEmpty == false)
        #expect(range.isIndefinite == false)

        #expect(CMTimeRange().isEmpty)
        #expect(CMTimeRange.zero.isValid)
        #expect(CMTimeRange.invalid.isValid == false)
    }

    @Test("Start and end construction rejects reversed and cross-epoch ranges")
    func startAndEndConstruction() {
        let start = CMTime(value: 2, timescale: 1)
        let end = CMTime(value: 5, timescale: 1)
        let range = CMTimeRange(start: start, end: end)

        #expect(range.start == start)
        #expect(range.duration == CMTime(value: 3, timescale: 1))
        #expect(CMTimeRange(start: end, end: start) == .invalid)

        let otherEpoch = CMTime(
            value: 5,
            timescale: 1,
            flags: .valid,
            epoch: 1
        )
        #expect(CMTimeRange(start: start, end: otherEpoch) == .invalid)
    }

    @Test("Validity follows duration epoch and sign rules")
    func validity() {
        let negative = CMTimeRange(
            start: .zero,
            duration: CMTime(value: -1, timescale: 1)
        )
        #expect(negative.isValid == false)

        let durationWithEpoch = CMTime(
            value: 1,
            timescale: 1,
            flags: .valid,
            epoch: 1
        )
        #expect(
            CMTimeRange(
                start: .zero,
                duration: durationWithEpoch
            ).isValid == false
        )

        #expect(
            CMTimeRange(
                start: .indefinite,
                duration: CMTime(value: 1, timescale: 1)
            ).isIndefinite
        )
        #expect(
            CMTimeRange(
                start: .zero,
                duration: .positiveInfinity
            ).isValid
        )
        #expect(
            CMTimeRange(
                start: .zero,
                duration: .negativeInfinity
            ).isValid
        )
    }

    @Test("Containment is half open")
    func containment() {
        let range = CMTimeRange(
            start: CMTime(value: 1, timescale: 1),
            duration: CMTime(value: 3, timescale: 1)
        )

        #expect(range.containsTime(range.start))
        #expect(range.containsTime(CMTime(value: 3, timescale: 1)))
        #expect(range.containsTime(range.end) == false)
        #expect(range.containsTime(CMTime(value: 0, timescale: 1)) == false)

        let contained = CMTimeRange(
            start: CMTime(value: 2, timescale: 1),
            duration: CMTime(value: 1, timescale: 1)
        )
        #expect(range.containsTimeRange(contained))
        #expect(range.containsTimeRange(.zero) == false)
        #expect(CMTimeRange.zero.containsTimeRange(.zero) == false)
        let emptyAtEnd = CMTimeRange(
            start: range.end,
            duration: .zero
        )
        #expect(range.containsTimeRange(emptyAtEnd) == false)
    }

    @Test("Intersection and union preserve Apple range behavior")
    func combinations() {
        let left = CMTimeRange(
            start: .zero,
            duration: CMTime(value: 2, timescale: 1)
        )
        let overlapping = CMTimeRange(
            start: CMTime(value: 1, timescale: 1),
            duration: CMTime(value: 3, timescale: 1)
        )

        #expect(
            left.intersection(overlapping)
                == CMTimeRange(
                    start: CMTime(value: 1, timescale: 1),
                    duration: CMTime(value: 1, timescale: 1)
                )
        )
        #expect(
            left.union(overlapping)
                == CMTimeRange(
                    start: .zero,
                    duration: CMTime(value: 4, timescale: 1)
                )
        )

        let disjoint = CMTimeRange(
            start: CMTime(value: 5, timescale: 1),
            duration: CMTime(value: 1, timescale: 1)
        )
        #expect(left.intersection(disjoint) == .zero)
        #expect(
            left.union(disjoint)
                == CMTimeRange(
                    start: .zero,
                    duration: CMTime(value: 6, timescale: 1)
                )
        )
    }
}
