public protocol CMVideoFormatDescription: CMFormatDescription {
    var dimensions: CVPixelDimensions { get }
    var pixelFormat: CVPixelFormatType { get }

    func matchesImageBuffer(
        _ imageBuffer: borrowing any CVPixelBuffer
    ) -> Bool
}
