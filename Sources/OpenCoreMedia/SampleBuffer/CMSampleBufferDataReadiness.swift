public enum CMSampleBufferDataReadiness: Sendable, Equatable {
    case notReady
    case ready
    case failed(code: Int32)
}
