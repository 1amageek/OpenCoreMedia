#if canImport(CoreFoundation) && canImport(CoreMedia) && canImport(CoreVideo)
import CoreFoundation
import CoreMedia
import CoreVideo
import OpenCoreMedia
import Testing

@Suite("Core Media attachment Apple differential")
struct CMAttachmentAppleDifferentialTests {
    @Test("Per-sample attachment copy matches Apple behavior")
    func perSampleAttachmentCopy() throws {
        let appleOriginal = try makeAppleSample()
        #expect(CoreMedia.CMSampleBufferGetSampleAttachmentsArray(
            appleOriginal,
            createIfNecessary: false
        ) == nil)

        var appleAttachments = appleOriginal.sampleAttachments
        #expect(appleAttachments.count == 1)
        #expect(Array(appleAttachments[0]).isEmpty)
        appleAttachments[0][.notSync] = true
        appleAttachments[0][.displayImmediately] = true
        appleOriginal.sampleAttachments = appleAttachments

        var replacementTiming = CoreMedia.CMSampleTimingInfo(
            duration: CoreMedia.CMTime(value: 1, timescale: 60),
            presentationTimeStamp: CoreMedia.CMTime(
                value: 20,
                timescale: 60
            ),
            decodeTimeStamp: .invalid
        )
        var appleCopy: CoreMedia.CMSampleBuffer?
        let copyStatus =
            CoreMedia.CMSampleBufferCreateCopyWithNewTiming(
                allocator: nil,
                sampleBuffer: appleOriginal,
                sampleTimingEntryCount: 1,
                sampleTimingArray: &replacementTiming,
                sampleBufferOut: &appleCopy
            )
        #expect(copyStatus == noErr)
        let requiredAppleCopy = try #require(appleCopy)
        #expect(CoreMedia.CMSampleBufferGetSampleAttachmentsArray(
            requiredAppleCopy,
            createIfNecessary: false
        ) != nil)
        #expect(
            requiredAppleCopy.sampleAttachments[0][.notSync]
                as? Bool == true
        )
        #expect(
            requiredAppleCopy.sampleAttachments[0][.displayImmediately]
                as? Bool == true
        )

        appleAttachments = appleOriginal.sampleAttachments
        appleAttachments[0][.notSync] = false
        appleOriginal.sampleAttachments = appleAttachments
        #expect(
            appleOriginal.sampleAttachments[0][.notSync]
                as? Bool == false
        )
        #expect(
            requiredAppleCopy.sampleAttachments[0][.notSync]
                as? Bool == true
        )
        #expect(
            CoreMedia.CMSampleBufferGetImageBuffer(appleOriginal)
                === CoreMedia.CMSampleBufferGetImageBuffer(
                    requiredAppleCopy
                )
        )

        let portableOriginal = try makePortableSample()
        #expect(
            OpenCoreMedia.CMSampleBufferGetSampleAttachmentsArray(
                portableOriginal,
                createIfNecessary: false
            ) == nil
        )
        let portableDictionary = portableOriginal.sampleAttachments[0]
        portableDictionary.setBoolean(true, for: .notSync)
        portableDictionary.setBoolean(
            true,
            for: .displayImmediately
        )
        let portableCopy = try portableOriginal.copy(
            withTiming: [
                OpenCoreMedia.CMSampleTimingInfo(
                    duration: OpenCoreMedia.CMTime(
                        value: 1,
                        timescale: 60
                    ),
                    presentationTimeStamp: OpenCoreMedia.CMTime(
                        value: 20,
                        timescale: 60
                    ),
                    decodeTimeStamp: .invalid
                )
            ]
        )
        let portableCopiedAttachments =
            OpenCoreMedia.CMSampleBufferGetSampleAttachmentsArray(
                portableCopy,
                createIfNecessary: false
            )
        let portableCopiedDictionary = try #require(
            portableCopiedAttachments
        )[0]
        #expect(
            try portableCopiedDictionary.booleanValue(
                for: .notSync
            ) == true
        )
        #expect(
            try portableCopiedDictionary.booleanValue(
                for: .displayImmediately
            ) == true
        )

        portableDictionary.setBoolean(false, for: .notSync)
        #expect(
            try portableDictionary.booleanValue(for: .notSync)
                == false
        )
        #expect(
            try portableCopiedDictionary.booleanValue(
                for: .notSync
            ) == true
        )
        #expect(
            try portableOriginal.imageBuffer()
                === portableCopy.imageBuffer()
        )
    }

    @Test("Timing copy matches Apple attachment propagation")
    func timingCopyPropagation() throws {
        let appleOriginal = try makeAppleSample()
        let propagatedKey = try makeCFString("test.propagated")
        let localKey = try makeCFString("test.local")

        CoreMedia.CMSetAttachment(
            appleOriginal,
            key: propagatedKey,
            value: kCFBooleanTrue,
            attachmentMode: CoreMedia.kCMAttachmentMode_ShouldPropagate
        )
        CoreMedia.CMSetAttachment(
            appleOriginal,
            key: localKey,
            value: kCFBooleanFalse,
            attachmentMode: CoreMedia.kCMAttachmentMode_ShouldNotPropagate
        )

        var replacementTiming = CoreMedia.CMSampleTimingInfo(
            duration: CoreMedia.CMTime(value: 1, timescale: 60),
            presentationTimeStamp: CoreMedia.CMTime(
                value: 20,
                timescale: 60
            ),
            decodeTimeStamp: .invalid
        )
        var appleCopy: CoreMedia.CMSampleBuffer?
        let copyStatus =
            CoreMedia.CMSampleBufferCreateCopyWithNewTiming(
                allocator: nil,
                sampleBuffer: appleOriginal,
                sampleTimingEntryCount: 1,
                sampleTimingArray: &replacementTiming,
                sampleBufferOut: &appleCopy
            )
        #expect(copyStatus == noErr)
        let requiredAppleCopy = try #require(appleCopy)

        var appleMode: CoreMedia.CMAttachmentMode = 0
        let applePropagated = CoreMedia.CMGetAttachment(
            requiredAppleCopy,
            key: propagatedKey,
            attachmentModeOut: &appleMode
        )
        let appleLocal = CoreMedia.CMGetAttachment(
            requiredAppleCopy,
            key: localKey,
            attachmentModeOut: nil
        )
        #expect(applePropagated != nil)
        #expect(
            appleMode == CoreMedia.kCMAttachmentMode_ShouldPropagate
        )
        #expect(appleLocal == nil)
        #expect(
            CoreMedia.CMSampleBufferGetImageBuffer(appleOriginal)
                === CoreMedia.CMSampleBufferGetImageBuffer(
                    requiredAppleCopy
                )
        )

        let portableFixture = try makePortableSample()
        let openPropagatedKey = OpenCoreMedia.CMAttachmentKey(
            rawValue: "test.propagated"
        )
        let openLocalKey = OpenCoreMedia.CMAttachmentKey(
            rawValue: "test.local"
        )
        OpenCoreMedia.CMSetAttachment(
            portableFixture,
            key: openPropagatedKey,
            value: .boolean(true),
            attachmentMode: .shouldPropagate
        )
        OpenCoreMedia.CMSetAttachment(
            portableFixture,
            key: openLocalKey,
            value: .boolean(false),
            attachmentMode: .shouldNotPropagate
        )
        let portableCopy = try portableFixture.copy(
            withTiming: [
                OpenCoreMedia.CMSampleTimingInfo(
                    duration: OpenCoreMedia.CMTime(
                        value: 1,
                        timescale: 60
                    ),
                    presentationTimeStamp: OpenCoreMedia.CMTime(
                        value: 20,
                        timescale: 60
                    ),
                    decodeTimeStamp: .invalid
                )
            ]
        )

        #expect(OpenCoreMedia.CMGetAttachment(
            portableCopy,
            key: openPropagatedKey
        )?.mode == .shouldPropagate)
        #expect(OpenCoreMedia.CMGetAttachment(
            portableCopy,
            key: openLocalKey
        ) == nil)
        #expect(
            try portableFixture.imageBuffer()
                === portableCopy.imageBuffer()
        )
    }

    private func makeAppleSample() throws -> CoreMedia.CMSampleBuffer {
        var imageBuffer: CoreVideo.CVPixelBuffer?
        let pixelStatus = CoreVideo.CVPixelBufferCreate(
            nil,
            2,
            1,
            CoreVideo.kCVPixelFormatType_32BGRA,
            nil,
            &imageBuffer
        )
        #expect(pixelStatus == CoreVideo.kCVReturnSuccess)
        let requiredImageBuffer = try #require(imageBuffer)

        var formatDescription: CoreMedia.CMVideoFormatDescription?
        let formatStatus =
            CoreMedia.CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: nil,
                imageBuffer: requiredImageBuffer,
                formatDescriptionOut: &formatDescription
            )
        #expect(formatStatus == noErr)
        let requiredFormat = try #require(formatDescription)

        var timing = CoreMedia.CMSampleTimingInfo(
            duration: CoreMedia.CMTime(value: 1, timescale: 30),
            presentationTimeStamp: CoreMedia.CMTime(
                value: 10,
                timescale: 30
            ),
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CoreMedia.CMSampleBuffer?
        let sampleStatus =
            CoreMedia.CMSampleBufferCreateReadyWithImageBuffer(
                allocator: nil,
                imageBuffer: requiredImageBuffer,
                formatDescription: requiredFormat,
                sampleTiming: &timing,
                sampleBufferOut: &sampleBuffer
            )
        #expect(sampleStatus == noErr)
        return try #require(sampleBuffer)
    }

    private func makePortableSample() throws -> CMImageSampleBuffer<
        CVPackedPixelBuffer<
            CVOwnedPixelBufferStorage<
                CVNoOpPixelBufferAccessCoordinator
            >,
            CVBufferAttachments
        >,
        CMImmutableVideoFormatDescription
    > {
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
        return try CMImageSampleBuffer(
            imageBuffer: image,
            formatDescription: format,
            timing: [
                OpenCoreMedia.CMSampleTimingInfo(
                    duration: OpenCoreMedia.CMTime(
                        value: 1,
                        timescale: 30
                    ),
                    presentationTimeStamp: OpenCoreMedia.CMTime(
                        value: 10,
                        timescale: 30
                    ),
                    decodeTimeStamp: .invalid
                )
            ]
        )
    }

    private func makeCFString(_ value: StaticString) throws -> CFString {
        let string = value.withUTF8Buffer { bytes in
            CFStringCreateWithBytes(
                nil,
                bytes.baseAddress,
                bytes.count,
                CFStringBuiltInEncodings.UTF8.rawValue,
                false
            )
        }
        return try #require(string)
    }
}
#endif
