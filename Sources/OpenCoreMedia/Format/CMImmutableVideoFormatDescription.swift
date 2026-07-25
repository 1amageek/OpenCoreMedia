public final class CMImmutableVideoFormatDescription:
    CMVideoFormatDescription,
    Sendable
{
    public let dimensions: CVPixelDimensions
    public let pixelFormat: CVPixelFormatType

    public var mediaType: CMMediaType {
        .video
    }

    public var mediaSubtype: UInt32 {
        pixelFormat.rawValue
    }

    public init(
        dimensions: CVPixelDimensions,
        pixelFormat: CVPixelFormatType
    ) {
        self.dimensions = dimensions
        self.pixelFormat = pixelFormat
    }

    public func matchesImageBuffer(
        _ imageBuffer: borrowing any CVPixelBuffer
    ) -> Bool {
        imageBuffer.dimensions == dimensions
            && imageBuffer.pixelFormat == pixelFormat
    }
}
