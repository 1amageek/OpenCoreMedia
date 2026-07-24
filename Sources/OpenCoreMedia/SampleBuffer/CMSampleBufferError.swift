public enum CMSampleBufferError: Error, Sendable, Equatable {
    case imagePayloadRequiresSingleSample(actual: Int)
    case timingCountMismatch(expected: Int, actual: Int)
    case formatDimensionsMismatch(
        expected: CVPixelDimensions,
        actual: CVPixelDimensions
    )
    case formatPixelTypeMismatch(
        expected: CVPixelFormatType,
        actual: CVPixelFormatType
    )
    case invalidPresentationTime
    case invalidDuration
    case invalidDecodeTime
    case sampleIndexOutOfBounds(index: Int, count: Int)
    case dataNotReady
    case dataFailed(code: Int32)
    case invalidated
}
