import Synchronization

public final class CMImageSampleBuffer<
    ImageBuffer: CVPixelBuffer,
    VideoFormat: CMVideoFormatDescription
>: CMSampleBuffer {
    private struct State: Sendable {
        var isValid: Bool
        var readiness: CMSampleBufferDataReadiness
        var sampleAttachmentStorages:
            [CMSampleAttachmentDictionaryStorage]?
    }

    private let image: ImageBuffer
    private let format: VideoFormat
    private let count: Int
    private let timing: CMSampleTimingInfo
    public let attachments = CMAttachmentBearerAttachments()

    private let state: Mutex<State>

    public var isValid: Bool {
        state.withLock { state in
            state.isValid
        }
    }

    public var dataReadiness: CMSampleBufferDataReadiness {
        state.withLock { state in
            state.readiness
        }
    }

    public var sampleAttachments: CMSampleAttachmentsArray {
        CMSampleAttachmentsArray(
            storages: materializedSampleAttachmentStorages()
        )
    }

    public init(
        imageBuffer: ImageBuffer,
        formatDescription: VideoFormat,
        sampleCount: Int = 1,
        timing: [CMSampleTimingInfo],
        dataReadiness: CMSampleBufferDataReadiness = .ready
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
        state = Mutex(State(
            isValid: true,
            readiness: dataReadiness,
            sampleAttachmentStorages: nil
        ))
    }

    public func sampleCount() throws(CMSampleBufferError) -> Int {
        try requireValid()
        return count
    }

    public func formatDescription()
        throws(CMSampleBufferError) -> VideoFormat
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
        throws(CMSampleBufferError) -> ImageBuffer
    {
        try requireReady()
        return image
    }

    public func copy(
        withTiming timing: [CMSampleTimingInfo]
    ) throws(CMSampleBufferError) -> CMImageSampleBuffer<
        ImageBuffer,
        VideoFormat
    > {
        let readiness = try currentReadiness()

        // The new sample buffer retains the same image-buffer reference.
        // Timing, readiness, and attachment metadata receive new storage.
        let copy = try CMImageSampleBuffer(
            imageBuffer: image,
            formatDescription: format,
            sampleCount: count,
            timing: timing,
            dataReadiness: readiness
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
            state.readiness = readiness
        }
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
        try state.withLock { state throws(CMSampleBufferError) in
            guard state.isValid else {
                throw .invalidated
            }
            return state.readiness
        }
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
        to destination: borrowing CMImageSampleBuffer<
            ImageBuffer,
            VideoFormat
        >
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
