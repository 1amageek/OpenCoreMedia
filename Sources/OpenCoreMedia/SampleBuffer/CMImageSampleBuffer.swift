import Synchronization

private struct CMImageSampleState: Sendable {
    var isValid: Bool
    var sampleAttachmentStorages:
        [CMSampleAttachmentDictionaryStorage]?
}

private final class CMImageSampleStateStorage: Sendable {
    private let state: CMStateLock<CMImageSampleState>

    init() {
        state = CMStateLock(CMImageSampleState(
            isValid: true,
            sampleAttachmentStorages: nil
        ))
    }

    func withLock<Result: ~Copyable, E: Error>(
        _ body: (
            inout sending CMImageSampleState
        ) throws(E) -> sending Result
    ) throws(E) -> sending Result {
        try state.withLock(body)
    }
}

public final class CMImageSampleBuffer: CMSampleBuffer {
    private let image: any CVPixelBuffer & Sendable
    private let format: any CMVideoFormatDescription
    private let count: Int
    private let timing: CMSampleTimingInfo
    private let readinessTracker: CMSampleDataReadinessTracker?
    public let attachments = CMAttachmentBearerAttachments()

    private let state: CMImageSampleStateStorage

    public var isValid: Bool {
        state.withLock { state in
            state.isValid
        }
    }

    public var dataReadiness: CMSampleBufferDataReadiness {
        readinessTracker?.readiness ?? .ready
    }

    public var sampleAttachments: CMSampleAttachmentsArray {
        CMSampleAttachmentsArray(
            storages: materializedSampleAttachmentStorages()
        )
    }

    public init(
        imageBuffer: any CVPixelBuffer & Sendable,
        formatDescription: any CMVideoFormatDescription,
        sampleCount: Int = 1,
        timing: [CMSampleTimingInfo],
        dataReadiness: CMSampleBufferDataReadiness = .ready,
        makeDataReadyHandler: CMSampleBufferMakeDataReadyHandler? = nil
    ) throws(CMSampleBufferError) {
        guard sampleCount == 1 else {
            throw .imagePayloadRequiresSingleSample(actual: sampleCount)
        }
        guard timing.count == sampleCount else {
            throw .timingCountMismatch(
                expected: sampleCount,
                actual: timing.count
            )
        }
        guard formatDescription.dimensions == imageBuffer.dimensions else {
            throw .formatDimensionsMismatch(
                expected: formatDescription.dimensions,
                actual: imageBuffer.dimensions
            )
        }
        guard formatDescription.pixelFormat == imageBuffer.pixelFormat else {
            throw .formatPixelTypeMismatch(
                expected: formatDescription.pixelFormat,
                actual: imageBuffer.pixelFormat
            )
        }

        let sampleTiming = timing[0]
        try Self.validate(sampleTiming)

        // The sample buffer retains the image buffer owner. No media bytes are
        // copied or materialized at this boundary.
        image = imageBuffer
        format = formatDescription
        count = sampleCount
        self.timing = sampleTiming
        state = CMImageSampleStateStorage()
        readinessTracker =
            dataReadiness == .ready && makeDataReadyHandler == nil
            ? nil
            : CMSampleDataReadinessTracker(
                readiness: dataReadiness,
                handler: makeDataReadyHandler
            )
    }

    private init(
        imageBuffer: any CVPixelBuffer & Sendable,
        formatDescription: any CMVideoFormatDescription,
        sampleCount: Int,
        timing: [CMSampleTimingInfo],
        readinessTracker: CMSampleDataReadinessTracker?
    ) throws(CMSampleBufferError) {
        guard sampleCount == 1 else {
            throw .imagePayloadRequiresSingleSample(actual: sampleCount)
        }
        guard timing.count == sampleCount else {
            throw .timingCountMismatch(
                expected: sampleCount,
                actual: timing.count
            )
        }
        guard formatDescription.dimensions == imageBuffer.dimensions else {
            throw .formatDimensionsMismatch(
                expected: formatDescription.dimensions,
                actual: imageBuffer.dimensions
            )
        }
        guard formatDescription.pixelFormat == imageBuffer.pixelFormat else {
            throw .formatPixelTypeMismatch(
                expected: formatDescription.pixelFormat,
                actual: imageBuffer.pixelFormat
            )
        }
        let sampleTiming = timing[0]
        try Self.validate(sampleTiming)

        image = imageBuffer
        format = formatDescription
        count = sampleCount
        self.timing = sampleTiming
        self.readinessTracker = readinessTracker
        state = CMImageSampleStateStorage()
    }

    public func sampleCount() throws(CMSampleBufferError) -> Int {
        try requireValid()
        return count
    }

    public func formatDescription()
        throws(CMSampleBufferError) -> any CMVideoFormatDescription
    {
        try requireValid()
        return format
    }

    public func timingInfo(
        at index: Int
    ) throws(CMSampleBufferError) -> CMSampleTimingInfo {
        try requireValid()
        guard index == 0 else {
            throw .sampleIndexOutOfBounds(index: index, count: count)
        }
        return timing
    }

    public func imageBuffer()
        throws(CMSampleBufferError) -> any CVPixelBuffer & Sendable
    {
        try requireReady()
        return image
    }

    public func copy(
        withTiming timing: [CMSampleTimingInfo]
    ) throws(CMSampleBufferError) -> CMImageSampleBuffer {
        _ = try currentReadiness()

        // The new sample buffer retains the same image-buffer reference.
        // Readiness tracking is shared while timing and attachments receive
        // independent metadata storage.
        let copy = try CMImageSampleBuffer(
            imageBuffer: image,
            formatDescription: format,
            sampleCount: count,
            timing: timing,
            readinessTracker: readinessTracker
        )
        CMPropagateAttachments(self, destination: copy)
        copySampleAttachments(to: copy)
        return copy
    }

    public func sampleAttachments(
        createIfNecessary: Bool
    ) -> CMSampleAttachmentsArray? {
        if createIfNecessary {
            return sampleAttachments
        }
        guard let storages = existingSampleAttachmentStorages()
        else {
            return nil
        }
        return CMSampleAttachmentsArray(storages: storages)
    }

    public func setDataReadiness(
        _ readiness: CMSampleBufferDataReadiness
    ) throws(CMSampleBufferError) {
        try state.withLock { state throws(CMSampleBufferError) in
            guard state.isValid else {
                throw .invalidated
            }
        }
        guard let readinessTracker else {
            guard readiness == .ready else {
                throw .invalidReadinessTransition(
                    from: .ready,
                    to: readiness
                )
            }
            return
        }
        try readinessTracker.set(readiness)
    }

    public func makeDataReady() async throws(CMSampleBufferError) {
        try requireValid()
        if let readinessTracker {
            try await readinessTracker.makeReady()
        }
        try requireValid()
    }

    public func invalidate() throws(CMSampleBufferError) {
        state.withLock { state in
            state.isValid = false
        }
    }

    private func requireValid() throws(CMSampleBufferError) {
        try state.withLock { state throws(CMSampleBufferError) in
            guard state.isValid else {
                throw .invalidated
            }
        }
    }

    private func requireReady() throws(CMSampleBufferError) {
        let readiness = try currentReadiness()
        switch readiness {
        case .ready:
            return
        case .notReady:
            throw .dataNotReady
        case .failed(let code):
            throw .dataFailed(code: code)
        }
    }

    private func currentReadiness()
        throws(CMSampleBufferError) -> CMSampleBufferDataReadiness
    {
        try requireValid()
        return readinessTracker?.readiness ?? .ready
    }

    private func materializedSampleAttachmentStorages()
        -> [CMSampleAttachmentDictionaryStorage]
    {
        state.withLock { state in
            if let storages = state.sampleAttachmentStorages {
                return storages
            }
            let created = Self.makeSampleAttachmentStorages(count: count)
            state.sampleAttachmentStorages = created
            return created
        }
    }

    private func existingSampleAttachmentStorages()
        -> [CMSampleAttachmentDictionaryStorage]?
    {
        state.withLock { state in
            state.sampleAttachmentStorages
        }
    }

    private func copySampleAttachments(
        to destination: borrowing CMImageSampleBuffer
    ) {
        guard let sourceStorages = existingSampleAttachmentStorages()
        else {
            return
        }

        var copiedStorages: [CMSampleAttachmentDictionaryStorage] = []
        copiedStorages.reserveCapacity(sourceStorages.count)
        for storage in sourceStorages {
            copiedStorages.append(storage.copy())
        }
        destination.installSampleAttachmentStorages(copiedStorages)
    }

    private func installSampleAttachmentStorages(
        _ storages: [CMSampleAttachmentDictionaryStorage]
    ) {
        state.withLock { state in
            state.sampleAttachmentStorages = storages
        }
    }

    private static func makeSampleAttachmentStorages(
        count: Int
    ) -> [CMSampleAttachmentDictionaryStorage] {
        var result: [CMSampleAttachmentDictionaryStorage] = []
        result.reserveCapacity(count)
        for _ in 0..<count {
            result.append(CMSampleAttachmentDictionaryStorage())
        }
        return result
    }

    private static func validate(
        _ timing: CMSampleTimingInfo
    ) throws(CMSampleBufferError) {
        guard timing.presentationTimeStamp.isNumeric,
              timing.presentationTimeStamp.timescale > 0
        else {
            throw .invalidPresentationTime
        }

        if timing.duration.isValid {
            guard timing.duration.isNumeric,
                  timing.duration.timescale > 0,
                  timing.duration >= .zero
            else {
                throw .invalidDuration
            }
        }

        if timing.decodeTimeStamp.isValid {
            guard timing.decodeTimeStamp.isNumeric,
                  timing.decodeTimeStamp.timescale > 0
            else {
                throw .invalidDecodeTime
            }
        }
    }
}
