import OpenCoreMedia
import Testing

@Suite("Image sample buffer smoke")
struct SampleBufferSmokeTests {
    @Test("Ready samples retain pixel storage without copying")
    func readySampleSharesPixelStorage() throws {
        let fixture = try makeFixture()
        let sample: any CMSampleBuffer = try CMImageSampleBuffer(
            imageBuffer: fixture.image,
            formatDescription: fixture.format,
            timing: [fixture.timing]
        )

        let retainedImage = try sample.imageBuffer()
        #expect(retainedImage === fixture.image)

        try fixture.image.withWriteBytes { bytes in
            bytes[0] = 41
            bytes[7] = 73
        }

        var observed: (UInt8, UInt8) = (0, 0)
        try retainedImage.withReadBytes { bytes in
            observed = (bytes[0], bytes[7])
        }
        #expect(observed.0 == 41)
        #expect(observed.1 == 73)
        #expect(try sample.sampleCount() == 1)
        #expect(try sample.timingInfo(at: 0) == fixture.timing)
        #expect(throws: CMSampleBufferError.sampleIndexOutOfBounds(
            index: -1,
            count: 1
        )) {
            _ = try sample.timingInfo(at: -1)
        }
        #expect(throws: CMSampleBufferError.sampleIndexOutOfBounds(
            index: 1,
            count: 1
        )) {
            _ = try sample.timingInfo(at: 1)
        }
    }

    @Test("Scalar timing construction preserves the zero-copy image contract")
    func scalarTimingConstructionSharesPixelStorage() throws {
        let fixture = try makeFixture()
        let sample = try CMImageSampleBuffer(
            imageBuffer: fixture.image,
            formatDescription: fixture.format,
            timing: fixture.timing
        )

        #expect(try sample.imageBuffer() === fixture.image)
        #expect(try sample.sampleCount() == 1)
        #expect(try sample.timingInfo(at: 0) == fixture.timing)
    }

    @Test("Timing copies share the original image storage")
    func timingCopySharesPixelStorage() throws {
        let fixture = try makeFixture()
        let original = try CMImageSampleBuffer(
            imageBuffer: fixture.image,
            formatDescription: fixture.format,
            timing: [fixture.timing]
        )
        let replacement = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 60),
            presentationTimeStamp: CMTime(value: 20, timescale: 60),
            decodeTimeStamp: .invalid
        )
        let copy = try original.copy(withTiming: [replacement])

        let originalImage = try original.imageBuffer()
        let copiedImage = try copy.imageBuffer()
        #expect(originalImage === copiedImage)
        #expect(copiedImage === fixture.image)

        try copiedImage.withWriteBytes { bytes in
            bytes[3] = 121
        }
        var value: UInt8 = 0
        try fixture.image.withReadBytes { bytes in
            value = bytes[3]
        }
        #expect(value == 121)
        #expect(try copy.timingInfo(at: 0) == replacement)
        #expect(try original.timingInfo(at: 0) == fixture.timing)
    }

    @Test("Timing copies propagate metadata into independent storage")
    func timingCopyPropagatesAttachments() throws {
        let fixture = try makeFixture()
        let original = try CMImageSampleBuffer(
            imageBuffer: fixture.image,
            formatDescription: fixture.format,
            timing: [fixture.timing]
        )
        let propagatedKey = CMAttachmentKey(rawValue: "test.propagated")
        let localKey = CMAttachmentKey(rawValue: "test.local")
        CMSetAttachment(
            original,
            key: propagatedKey,
            value: .integer(17),
            attachmentMode: .shouldPropagate
        )
        CMSetAttachment(
            original,
            key: localKey,
            value: .boolean(true),
            attachmentMode: .shouldNotPropagate
        )

        let copy = try original.copy(withTiming: [fixture.timing])

        #expect(try original.imageBuffer() === copy.imageBuffer())
        #expect(CMGetAttachment(
            copy,
            key: propagatedKey
        ) == CMAttachment(
            value: .integer(17),
            mode: .shouldPropagate
        ))
        #expect(CMGetAttachment(copy, key: localKey) == nil)

        CMSetAttachment(
            original,
            key: propagatedKey,
            value: .integer(29),
            attachmentMode: .shouldPropagate
        )
        #expect(CMGetAttachment(
            copy,
            key: propagatedKey
        )?.value == .integer(17))

        CMRemoveAttachment(copy, key: propagatedKey)
        #expect(CMGetAttachment(copy, key: propagatedKey) == nil)
        #expect(CMGetAttachment(
            original,
            key: propagatedKey
        )?.value == .integer(29))
    }

    @Test("Sample count and timing mismatches are typed failures")
    func countAndTimingFailures() throws {
        let fixture = try makeFixture()

        #expect(throws: CMSampleBufferError.imagePayloadRequiresSingleSample(
            actual: 2
        )) {
            _ = try CMImageSampleBuffer(
                imageBuffer: fixture.image,
                formatDescription: fixture.format,
                sampleCount: 2,
                timing: [fixture.timing, fixture.timing]
            )
        }

        #expect(throws: CMSampleBufferError.timingCountMismatch(
            expected: 1,
            actual: 0
        )) {
            _ = try CMImageSampleBuffer(
                imageBuffer: fixture.image,
                formatDescription: fixture.format,
                timing: []
            )
        }

        let sample = try CMImageSampleBuffer(
            imageBuffer: fixture.image,
            formatDescription: fixture.format,
            timing: fixture.timing
        )
        #expect(throws: CMSampleBufferError.timingCountMismatch(
            expected: 1,
            actual: 0
        )) {
            _ = try sample.copy(withTiming: [])
        }
    }

    @Test("Format mismatches are typed failures")
    func formatFailures() throws {
        let fixture = try makeFixture()
        let otherDimensions = try CVPixelDimensions(width: 1, height: 2)
        let wrongDimensions = CMImmutableVideoFormatDescription(
            dimensions: otherDimensions,
            pixelFormat: .bgra32
        )

        #expect(throws: CMSampleBufferError.formatDimensionsMismatch(
            expected: otherDimensions,
            actual: fixture.image.dimensions
        )) {
            _ = try CMImageSampleBuffer(
                imageBuffer: fixture.image,
                formatDescription: wrongDimensions,
                timing: [fixture.timing]
            )
        }

        let wrongPixelType = CMImmutableVideoFormatDescription(
            dimensions: fixture.image.dimensions,
            pixelFormat: .rgba32
        )
        #expect(throws: CMSampleBufferError.formatPixelTypeMismatch(
            expected: .rgba32,
            actual: .bgra32
        )) {
            _ = try CMImageSampleBuffer(
                imageBuffer: fixture.image,
                formatDescription: wrongPixelType,
                timing: [fixture.timing]
            )
        }
    }

    @Test("Invalid timing is rejected")
    func timingFailures() throws {
        let fixture = try makeFixture()
        let invalidPresentation = CMSampleTimingInfo(
            duration: fixture.timing.duration,
            presentationTimeStamp: .invalid,
            decodeTimeStamp: .invalid
        )
        #expect(throws: CMSampleBufferError.invalidPresentationTime) {
            _ = try CMImageSampleBuffer(
                imageBuffer: fixture.image,
                formatDescription: fixture.format,
                timing: [invalidPresentation]
            )
        }

        let negativeDuration = CMSampleTimingInfo(
            duration: CMTime(value: -1, timescale: 30),
            presentationTimeStamp: fixture.timing.presentationTimeStamp,
            decodeTimeStamp: .invalid
        )
        #expect(throws: CMSampleBufferError.invalidDuration) {
            _ = try CMImageSampleBuffer(
                imageBuffer: fixture.image,
                formatDescription: fixture.format,
                timing: [negativeDuration]
            )
        }
    }

    @Test("Unready, failed, and invalidated access never looks successful")
    func stateFailures() throws {
        let fixture = try makeFixture()
        let sample = try CMImageSampleBuffer(
            imageBuffer: fixture.image,
            formatDescription: fixture.format,
            timing: [fixture.timing],
            dataReadiness: .notReady
        )

        #expect(throws: CMSampleBufferError.dataNotReady) {
            _ = try sample.imageBuffer()
        }

        try sample.setDataReadiness(.failed(code: 19))
        #expect(throws: CMSampleBufferError.dataFailed(code: 19)) {
            _ = try sample.imageBuffer()
        }

        #expect(throws: CMSampleBufferError.invalidReadinessTransition(
            from: .failed(code: 19),
            to: .ready
        )) {
            try sample.setDataReadiness(.ready)
        }
        #expect(throws: CMSampleBufferError.dataFailed(code: 19)) {
            _ = try sample.imageBuffer()
        }

        try sample.invalidate()
        try sample.invalidate()
        #expect(sample.isValid == false)
        #expect(throws: CMSampleBufferError.invalidated) {
            _ = try sample.imageBuffer()
        }
        #expect(throws: CMSampleBufferError.invalidated) {
            _ = try sample.sampleCount()
        }
        #expect(throws: CMSampleBufferError.invalidated) {
            _ = try sample.formatDescription()
        }
        #expect(throws: CMSampleBufferError.invalidated) {
            _ = try sample.timingInfo(at: 0)
        }
    }

    private func makeFixture() throws -> (
        image: TestPixelBuffer,
        format: CMImmutableVideoFormatDescription,
        timing: CMSampleTimingInfo
    ) {
        let dimensions = try CVPixelDimensions(width: 2, height: 1)
        let image = try CVPackedPixelBuffer(
            dimensions: dimensions,
            pixelFormat: .bgra32,
            bytesPerPixel: 4,
            bytesPerRow: 8
        )
        let format = CMImmutableVideoFormatDescription(
            dimensions: dimensions,
            pixelFormat: .bgra32
        )
        let timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: CMTime(value: 10, timescale: 30),
            decodeTimeStamp: .invalid
        )
        return (image, format, timing)
    }
}

private typealias TestPixelBuffer = CVPackedPixelBuffer<
    CVOwnedPixelBufferStorage<CVNoOpPixelBufferAccessCoordinator>,
    CVBufferAttachments
>
