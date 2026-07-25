import OpenCoreMedia
import Testing

@Suite("CMTime smoke")
struct CMTimeSmokeTests {
    @Test("Special values expose the documented predicates")
    func specialValues() {
        #expect(CMTime().isValid == false)
        #expect(CMTime.invalid.isNumeric == false)
        #expect(CMTime.zero.isNumeric)
        #expect(CMTime.indefinite.isIndefinite)
        #expect(CMTime.positiveInfinity.isPositiveInfinity)
        #expect(CMTime.negativeInfinity.isNegativeInfinity)
        #expect(CMTime(value: 1, timescale: 0) == .invalid)
        #expect(CMTime(value: 1, timescale: -1) == .invalid)
    }

    @Test("Addition uses an exact common timescale")
    func exactAddition() {
        let half = CMTime(value: 1, timescale: 2)
        let third = CMTime(value: 1, timescale: 3)
        let result = half + third

        #expect(result.value == 5)
        #expect(result.timescale == 6)
        #expect(result.epoch == 0)
        #expect(result.hasBeenRounded == false)
    }

    @Test("Arithmetic preserves the documented epoch rules")
    func epochArithmetic() {
        let epochTime = CMTime(
            value: 2,
            timescale: 1,
            flags: .valid,
            epoch: 3
        )
        let duration = CMTime(value: 1, timescale: 1)
        let sameEpoch = CMTime(
            value: 4,
            timescale: 1,
            flags: .valid,
            epoch: 3
        )
        let otherEpoch = CMTime(
            value: 4,
            timescale: 1,
            flags: .valid,
            epoch: 4
        )

        #expect((epochTime + duration).epoch == 3)
        #expect((epochTime + sameEpoch).epoch == 0)
        #expect(epochTime + otherEpoch == .invalid)
    }

    @Test("Overflow is checked and never wraps")
    func checkedOverflow() {
        let maximum = CMTime(value: .max, timescale: 1)
        let overflow = maximum + maximum

        #expect(overflow.isPositiveInfinity)
        #expect(overflow.hasBeenRounded == false)

        let minimum = CMTime(value: .min, timescale: 1)
        let negativeOverflow = minimum + minimum
        #expect(negativeOverflow.isNegativeInfinity)
        #expect(negativeOverflow.hasBeenRounded == false)
    }

    @Test("Scale conversion applies explicit rounding")
    func scaleConversion() {
        let source = CMTime(value: 2, timescale: 3)

        let towardZero = source.convertScale(1, method: .roundTowardZero)
        #expect(towardZero.value == 0)
        #expect(towardZero.timescale == 1)
        #expect(towardZero.hasBeenRounded)

        let away = source.convertScale(1, method: .roundAwayFromZero)
        #expect(away.value == 1)
        #expect(away.hasBeenRounded)

        let negative = CMTime(value: -2, timescale: 3)
        #expect(
            negative.convertScale(
                1,
                method: .roundTowardNegativeInfinity
            ).value == -1
        )
    }

    @Test("Comparison is exact for large rational values")
    func exactComparison() {
        let left = CMTime(value: .max, timescale: 2)
        let right = CMTime(value: .max - 1, timescale: 2)

        #expect(left > right)
        #expect(CMTime(value: 1, timescale: 2) == CMTime(value: 2, timescale: 4))
        #expect(CMTime.negativeInfinity < CMTime.zero)
        #expect(CMTime.zero < CMTime.indefinite)
        #expect(CMTime.indefinite < CMTime.positiveInfinity)
        #expect(CMTime.positiveInfinity < CMTime.invalid)
    }

    @Test("Timing info has value semantics")
    func timingInfo() {
        let timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: CMTime(value: 10, timescale: 30),
            decodeTimeStamp: .invalid
        )

        #expect(timing.duration == CMTime(value: 1, timescale: 30))
        #expect(timing.presentationTimeStamp == CMTime(value: 1, timescale: 3))
        #expect(timing.decodeTimeStamp == .invalid)
        #expect(CMSampleTimingInfo() == .invalid)
    }
}
