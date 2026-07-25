import OpenCoreMedia

@main
struct OpenCoreMediaEmbeddedSmoke {
    static func main() throws {
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
            presentationTimeStamp: CMTime(
                value: 10,
                timescale: 30
            ),
            decodeTimeStamp: .invalid
        )
        let sample = try CMImageSampleBuffer(
            imageBuffer: image,
            formatDescription: format,
            timing: [timing]
        )

        guard sample.sampleAttachments(
            createIfNecessary: false
        ) == nil else {
            throw OpenCoreMediaEmbeddedSmokeError.unexpectedMaterialization
        }

        let source = sample.sampleAttachments[0]
        source.setBoolean(true, for: .notSync)
        source[rawAttachment: "smoke.metadata"] = .array([
            .integer(1),
            .dictionary(["ready": .boolean(true)])
        ])
        let propagatedKey = CMAttachmentKey(
            rawValue: "smoke.propagated"
        )
        sample.attachments[propagatedKey] = .shouldPropagate(
            .integer(7)
        )

        try sample.setDataReadiness(.notReady)
        do {
            _ = try sample.imageBuffer()
            throw OpenCoreMediaEmbeddedSmokeError.readinessIgnored
        } catch CMSampleBufferError.dataNotReady {
        }
        try sample.setDataReadiness(.failed(code: 17))
        do {
            _ = try sample.imageBuffer()
            throw OpenCoreMediaEmbeddedSmokeError.readinessFailureIgnored
        } catch CMSampleBufferError.dataFailed(code: 17) {
        }
        try sample.setDataReadiness(.ready)

        let pointer = UnsafeMutableRawPointer.allocate(
            byteCount: 8,
            alignment: 8
        )
        let block = try CMBlockBuffer(
            buffer: UnsafeMutableRawBufferPointer(
                start: pointer,
                count: 8
            ),
            deallocator: { releasedPointer, _ in
                releasedPointer.deallocate()
            }
        )
        do {
            try block.withContiguousStorage { _ -> Void in
                throw OpenCoreMediaEmbeddedBorrowError.expected
            }
            throw OpenCoreMediaEmbeddedSmokeError.borrowFailureIgnored
        } catch OpenCoreMediaEmbeddedBorrowError.expected {
        }

        let copy = try sample.copy(withTiming: [timing])
        let copied = copy.sampleAttachments[0]
        guard try copied.booleanValue(for: .notSync) == true,
              copied[rawAttachment: "smoke.metadata"] == .array([
                  .integer(1),
                  .dictionary(["ready": .boolean(true)])
              ]),
              copy.attachments[propagatedKey] == .shouldPropagate(
                  .integer(7)
              ),
              try sample.imageBuffer() === copy.imageBuffer()
        else {
            throw OpenCoreMediaEmbeddedSmokeError.copyContractViolated
        }

        source.setBoolean(false, for: .notSync)
        guard try copied.booleanValue(for: .notSync) == true else {
            throw OpenCoreMediaEmbeddedSmokeError.metadataAliased
        }
    }
}

enum OpenCoreMediaEmbeddedSmokeError: Error {
    case unexpectedMaterialization
    case readinessIgnored
    case readinessFailureIgnored
    case borrowFailureIgnored
    case copyContractViolated
    case metadataAliased
}

enum OpenCoreMediaEmbeddedBorrowError: Error {
    case expected
}
