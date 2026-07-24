public protocol CMVideoFormatDescription: CMFormatDescription {
    var dimensions: CVPixelDimensions { get }
    var pixelFormat: CVPixelFormatType { get }

    func matchesImageBuffer<Buffer: CVPixelBuffer>(
        _ imageBuffer: borrowing Buffer
    ) -> Bool
}
