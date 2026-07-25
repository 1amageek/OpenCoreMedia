import OpenCoreMedia
import Testing

@Suite("Core Media per-sample attachment smoke")
struct CMSampleAttachmentSmokeTests {
    @Test("Attachment arrays are lazy, fixed-length mutable views")
    func lazyMaterialization() throws {
        let sample = try makeSample()

        #expect(OpenCoreMedia.CMSampleBufferGetSampleAttachmentsArray(
            sample,
            createIfNecessary: false
        ) == nil)

        let createdAttachments =
            OpenCoreMedia.CMSampleBufferGetSampleAttachmentsArray(
                sample,
                createIfNecessary: true
            )
        let attachments = try #require(
            createdAttachments
        )
        #expect(attachments.count == 1)
        #expect(attachments[0].isEmpty)
        #expect(
            try attachments[0].booleanValue(for: .notSync) == nil
        )

        let first = try attachments.attachment(at: 0)
        first.setBoolean(true, for: .notSync)
        sample.sampleAttachments[0][.displayImmediately] =
            .boolean(true)
        first[rawAttachment: "test.metadata"] = .dictionary([
            "labels": .array([
                .string("person"),
                .string("gesture")
            ]),
            "confidence": .floatingPoint(0.875)
        ])

        #expect(try first.booleanValue(for: .notSync) == true)
        #expect(
            try first.booleanValue(for: .displayImmediately) == true
        )
        #expect(first[rawAttachment: "test.metadata"] == .dictionary([
            "labels": .array([
                .string("person"),
                .string("gesture")
            ]),
            "confidence": .floatingPoint(0.875)
        ]))
        #expect(OpenCoreMedia.CMSampleBufferGetSampleAttachmentsArray(
            sample,
            createIfNecessary: false
        )?.count == 1)

        let enumerated = Dictionary(
            uniqueKeysWithValues: first.map { ($0.key, $0.value) }
        )
        #expect(enumerated == first.dictionaryRepresentation)

        first[.displayImmediately] = nil
        #expect(first[.displayImmediately] == nil)
        #expect(try first.booleanValue(for: .notSync) == true)
        first[rawAttachment: "test.metadata"] = nil
        #expect(first[rawAttachment: "test.metadata"] == nil)
        #expect(try first.booleanValue(for: .notSync) == true)

        #expect(throws: CMSampleBufferError.sampleIndexOutOfBounds(
            index: -1,
            count: 1
        )) {
            _ = try attachments.attachment(at: -1)
        }
        #expect(throws: CMSampleBufferError.sampleIndexOutOfBounds(
            index: 1,
            count: 1
        )) {
            _ = try attachments.attachment(at: 1)
        }
    }

    @Test("Standard-key type mismatches remain typed failures")
    func typedValueFailure() throws {
        let sample = try makeSample()
        let first = sample.sampleAttachments[0]
        first[.dependsOnOthers] = .integer(1)

        #expect(throws: CMSampleAttachmentError.valueIsNotBoolean(
            key: .dependsOnOthers
        )) {
            _ = try first.booleanValue(for: .dependsOnOthers)
        }
    }

    @Test("Standard keys match Core Media raw values")
    func standardKeyRawValues() {
        let rawValues: [(CMSampleAttachmentKey, String)] = [
            (.notSync, "NotSync"),
            (.partialSync, "PartialSync"),
            (.hasRedundantCoding, "HasRedundantCoding"),
            (.isDependedOnByOthers, "IsDependedOnByOthers"),
            (.dependsOnOthers, "DependsOnOthers"),
            (
                .earlierDisplayTimesAllowed,
                "EarlierDisplayTimesAllowed"
            ),
            (.displayImmediately, "DisplayImmediately"),
            (.doNotDisplay, "DoNotDisplay"),
            (.hevcTemporalLevelInfo, "HEVCTemporalLevelInfo"),
            (
                .hevcTemporalSubLayerAccess,
                "HEVCTemporalSubLayerAccess"
            ),
            (
                .hevcStepwiseTemporalSubLayerAccess,
                "HEVCStepwiseTemporalSubLayerAccess"
            ),
            (
                .hevcSyncSampleNALUnitType,
                "HEVCSyncSampleNALUnitType"
            ),
            (
                .audioIndependentSampleDecoderRefreshCount,
                "AudioIndependentSampleDecoderRefreshCount"
            )
        ]

        for (key, expectedRawValue) in rawValues {
            #expect(key.rawValue == expectedRawValue)
        }
    }

    @Test("Timing copies preserve metadata independently and share pixels")
    func timingCopy() throws {
        let original = try makeSample()
        let unmaterializedCopy = try original.copy(
            withTiming: [Self.replacementTiming()]
        )
        #expect(OpenCoreMedia.CMSampleBufferGetSampleAttachmentsArray(
            unmaterializedCopy,
            createIfNecessary: false
        ) == nil)

        let originalDictionary = original.sampleAttachments[0]
        originalDictionary.setBoolean(true, for: .notSync)
        originalDictionary[rawAttachment: "test.sequence"] = .array([
            .integer(3),
            .integer(5),
            .integer(8)
        ])

        let copy = try original.copy(
            withTiming: [Self.replacementTiming()]
        )
        let copiedAttachments =
            OpenCoreMedia.CMSampleBufferGetSampleAttachmentsArray(
                copy,
                createIfNecessary: false
            )
        let copiedDictionary = try #require(copiedAttachments)[0]

        #expect(try original.imageBuffer() === copy.imageBuffer())
        #expect(try copiedDictionary.booleanValue(for: .notSync) == true)
        #expect(copiedDictionary[rawAttachment: "test.sequence"] == .array([
            .integer(3),
            .integer(5),
            .integer(8)
        ]))

        originalDictionary.setBoolean(false, for: .notSync)
        originalDictionary[rawAttachment: "test.sequence"] = .array([
            .integer(13)
        ])
        #expect(try originalDictionary.booleanValue(for: .notSync) == false)
        #expect(try copiedDictionary.booleanValue(for: .notSync) == true)
        #expect(copiedDictionary[rawAttachment: "test.sequence"] == .array([
            .integer(3),
            .integer(5),
            .integer(8)
        ]))

        copiedDictionary.removeAll()
        #expect(copiedDictionary.isEmpty)
        #expect(!originalDictionary.isEmpty)
    }

    @Test("Concurrent mutation and timing copy stay race-safe")
    func concurrentMutationAndCopy() async throws {
        let sample = try makeSample()
        let attachment = sample.sampleAttachments[0]

        try await withThrowingTaskGroup(of: Void.self) { group in
            for worker in 0..<4 {
                group.addTask {
                    let key = CMSampleAttachmentKey(
                        rawValue: "test.worker.\(worker)"
                    )
                    for value in 0..<50 {
                        attachment[key] = .integer(Int64(value))
                        _ = attachment[key]
                        let copy = try sample.copy(
                            withTiming: [Self.replacementTiming()]
                        )
                        _ = copy.sampleAttachments[0][key]
                    }
                }
            }
            try await group.waitForAll()
        }

        for worker in 0..<4 {
            let key = CMSampleAttachmentKey(
                rawValue: "test.worker.\(worker)"
            )
            #expect(attachment[key] == .integer(49))
        }
    }

    @Test("Readiness and lazy materialization remain race-safe")
    func concurrentReadinessAndMaterialization() async throws {
        let sample = try makeSample()

        try await withThrowingTaskGroup(of: Void.self) { group in
            for worker in 0..<4 {
                group.addTask {
                    let key = CMSampleAttachmentKey(
                        rawValue: "test.materialization.\(worker)"
                    )
                    for value in 0..<50 {
                        let readiness: CMSampleBufferDataReadiness =
                            value.isMultiple(of: 2) ? .notReady : .ready
                        try sample.setDataReadiness(readiness)
                        _ = sample.dataReadiness

                        let attachment = sample.sampleAttachments[0]
                        attachment[key] = .integer(Int64(value))
                        _ = attachment[key]
                    }
                }
            }
            try await group.waitForAll()
        }

        try sample.setDataReadiness(.ready)
        _ = try sample.imageBuffer()
        let attachment = sample.sampleAttachments[0]
        for worker in 0..<4 {
            let key = CMSampleAttachmentKey(
                rawValue: "test.materialization.\(worker)"
            )
            #expect(attachment[key] == .integer(49))
        }
    }

    private func makeSample() throws -> CMImageSampleBuffer<
        SampleAttachmentTestPixelBuffer,
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
                CMSampleTimingInfo(
                    duration: CMTime(value: 1, timescale: 30),
                    presentationTimeStamp: CMTime(
                        value: 10,
                        timescale: 30
                    ),
                    decodeTimeStamp: .invalid
                )
            ]
        )
    }

    private static func replacementTiming() -> CMSampleTimingInfo {
        CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 60),
            presentationTimeStamp: CMTime(
                value: 20,
                timescale: 60
            ),
            decodeTimeStamp: .invalid
        )
    }
}

private typealias SampleAttachmentTestPixelBuffer = CVPackedPixelBuffer<
    CVOwnedPixelBufferStorage<CVNoOpPixelBufferAccessCoordinator>,
    CVBufferAttachments
>
