public enum CMSampleBufferError: Error, Sendable, Equatable {
    case imagePayloadRequiresSingleSample(actual: Int)
    case timingCountMismatch(expected: Int, actual: Int)
    case invalidSampleCount(Int)
    case sampleSizeCountMismatch(sampleCount: Int, sizeCount: Int)
    case sampleSizeOverflow
    case sampleDataLengthMismatch(expected: Int, actual: Int)
    case sampleSizeUnavailable
    case blockBuffer(CMBlockBufferError)
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
    case dataLoadingInProgress
    case dataFailed(code: Int32)
    case invalidReadinessTransition(
        from: CMSampleBufferDataReadiness,
        to: CMSampleBufferDataReadiness
    )
    case invalidated
}
