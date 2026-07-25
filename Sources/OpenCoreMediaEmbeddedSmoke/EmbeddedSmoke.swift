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

        let copy = try sample.copy(withTiming: [timing])
        let copied = copy.sampleAttachments[0]
        guard try copied.booleanValue(for: .notSync) == true,
              copied[rawAttachment: "smoke.metadata"] == .array([
                  .integer(1),
                  .dictionary(["ready": .boolean(true)])
              ]),
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
    case copyContractViolated
    case metadataAliased
}
