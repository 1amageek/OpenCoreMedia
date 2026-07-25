import Synchronization

private enum CMBlockSampleTimingLayout: Sendable {
    case invalid
    case uniform(CMSampleTimingInfo)
    case individual([CMSampleTimingInfo])

    func timing(
        at index: Int
    ) throws(CMSampleBufferError) -> CMSampleTimingInfo {
        switch self {
        case .invalid:
            return .invalid
        case .individual(let timings):
            return timings[index]
        case .uniform(var timing):
            guard index > 0, timing.duration.isNumeric else {
                return timing
            }
            let (scaledDuration, overflow) =
                timing.duration.value.multipliedReportingOverflow(
                    by: Int64(index)
                )
            guard !overflow else {
                throw .invalidDuration
            }
            let offset = CMTime(
                value: scaledDuration,
                timescale: timing.duration.timescale
            )
            timing.presentationTimeStamp =
                timing.presentationTimeStamp + offset
            guard timing.presentationTimeStamp.isNumeric else {
                throw .invalidPresentationTime
            }
            if timing.decodeTimeStamp.isNumeric {
                timing.decodeTimeStamp =
                    timing.decodeTimeStamp + offset
                guard timing.decodeTimeStamp.isNumeric else {
                    throw .invalidDecodeTime
                }
            }
            return timing
        }
    }
}

private enum CMBlockSampleSizeLayout: Sendable {
    case unavailable
    case uniform(Int)
    case individual(sizes: [Int], offsets: [Int])

    var constructorSizes: [Int] {
        switch self {
        case .unavailable:
            return []
        case .uniform(let size):
            return [size]
        case .individual(let sizes, _):
            return sizes
        }
    }

    func size(at index: Int) -> Int? {
        switch self {
        case .unavailable:
            return nil
        case .uniform(let size):
            return size
        case .individual(let sizes, _):
            return sizes[index]
        }
    }

    func range(at index: Int) -> Range<Int>? {
        switch self {
        case .unavailable:
            return nil
        case .uniform(let size):
            let lowerBound = size * index
            return lowerBound..<(lowerBound + size)
        case .individual(_, let offsets):
            return offsets[index]..<offsets[index + 1]
        }
    }
}

private struct CMBlockSampleState: Sendable {
    var isValid: Bool
    var sampleAttachmentStorages:
        [CMSampleAttachmentDictionaryStorage]?
}

private final class CMBlockSampleStateStorage: Sendable {
    private let state: CMStateLock<CMBlockSampleState>
    let attachments = CMAttachmentBearerAttachments()

    init() {
        state = CMStateLock(CMBlockSampleState(
            isValid: true,
            sampleAttachmentStorages: nil
        ))
    }

    func withLock<Result: ~Copyable, E: Error>(
        _ body: (
            inout sending CMBlockSampleState
        ) throws(E) -> sending Result
    ) throws(E) -> sending Result {
        try state.withLock(body)
    }
}

public final class CMBlockSampleBuffer: CMBlockSampleBufferProtocol {
    private let blockBuffer: CMBlockBuffer
    private let format: any CMFormatDescription
    private let count: Int
    private let timingLayout: CMBlockSampleTimingLayout
    private let sizeLayout: CMBlockSampleSizeLayout
    private let readinessTracker: CMSampleDataReadinessTracker?
    private let state: CMBlockSampleStateStorage

    public var attachments: CMAttachmentBearerAttachments {
        state.attachments
    }

    public var isValid: Bool {
        state.withLock { $0.isValid }
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
        dataBuffer: CMBlockBuffer,
        formatDescription: any CMFormatDescription,
        sampleCount: Int,
        timing: [CMSampleTimingInfo],
        sampleSizes: [Int],
        dataReadiness: CMSampleBufferDataReadiness = .ready,
        makeDataReadyHandler: CMSampleBufferMakeDataReadyHandler? = nil
    ) throws(CMSampleBufferError) {
        guard sampleCount > 0 else {
            throw .invalidSampleCount(sampleCount)
        }
        let timingLayout = try Self.timingLayout(
            timing,
            sampleCount: sampleCount
        )
        let sizeLayout = try Self.sizeLayout(
            sampleSizes,
            sampleCount: sampleCount
        )
        if let requiredLength = Self.totalSize(
            sizeLayout,
            sampleCount: sampleCount
        ) {
            guard requiredLength == dataBuffer.dataLength else {
                throw .sampleDataLengthMismatch(
                    expected: requiredLength,
                    actual: dataBuffer.dataLength
                )
            }
        }

        blockBuffer = dataBuffer
        format = formatDescription
        count = sampleCount
        self.timingLayout = timingLayout
        self.sizeLayout = sizeLayout
        state = CMBlockSampleStateStorage()
        readinessTracker =
            dataReadiness == .ready && makeDataReadyHandler == nil
            ? nil
            : CMSampleDataReadinessTracker(
                readiness: dataReadiness,
                handler: makeDataReadyHandler
            )
    }

    private init(
        dataBuffer: CMBlockBuffer,
        formatDescription: any CMFormatDescription,
        sampleCount: Int,
        timing: [CMSampleTimingInfo],
        sampleSizes: [Int],
        readinessTracker: CMSampleDataReadinessTracker?
    ) throws(CMSampleBufferError) {
        guard sampleCount > 0 else {
            throw .invalidSampleCount(sampleCount)
        }
        let timingLayout = try Self.timingLayout(
            timing,
            sampleCount: sampleCount
        )
        let sizeLayout = try Self.sizeLayout(
            sampleSizes,
            sampleCount: sampleCount
        )
        if let requiredLength = Self.totalSize(
            sizeLayout,
            sampleCount: sampleCount
        ) {
            guard requiredLength == dataBuffer.dataLength else {
                throw .sampleDataLengthMismatch(
                    expected: requiredLength,
                    actual: dataBuffer.dataLength
                )
            }
        }

        blockBuffer = dataBuffer
        format = formatDescription
        count = sampleCount
        self.timingLayout = timingLayout
        self.sizeLayout = sizeLayout
        self.readinessTracker = readinessTracker
        state = CMBlockSampleStateStorage()
    }

    public func sampleCount() throws(CMSampleBufferError) -> Int {
        try requireValid()
        return count
    }

    public func formatDescription()
        throws(CMSampleBufferError) -> any CMFormatDescription
    {
        try requireValid()
        return format
    }

    public func timingInfo(
        at index: Int
    ) throws(CMSampleBufferError) -> CMSampleTimingInfo {
        try requireValid()
        try validateSampleIndex(index)
        return try timingLayout.timing(at: index)
    }

    public func sampleSize(
        at index: Int
    ) throws(CMSampleBufferError) -> Int? {
        try requireValid()
        try validateSampleIndex(index)
        return sizeLayout.size(at: index)
    }

    public func dataBuffer() throws(CMSampleBufferError) -> CMBlockBuffer {
        try requireReady()
        return blockBuffer
    }

    public func sampleData(
        at index: Int
    ) throws(CMSampleBufferError) -> CMBlockBuffer.Slice {
        try requireReady()
        try validateSampleIndex(index)
        guard let sampleRange = sizeLayout.range(at: index) else {
            throw .sampleSizeUnavailable
        }
        do {
            return try blockBuffer.slice(sampleRange)
        } catch {
            throw .blockBuffer(error)
        }
    }

    public func sampleAttachments(
        createIfNecessary: Bool
    ) -> CMSampleAttachmentsArray? {
        if createIfNecessary {
            return sampleAttachments
        }
        guard let storages = existingSampleAttachmentStorages() else {
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
        state.withLock { $0.isValid = false }
    }

    public func copy(
        withTiming timing: [CMSampleTimingInfo]
    ) throws(CMSampleBufferError) -> CMBlockSampleBuffer {
        _ = try currentReadiness()
        let copy = try CMBlockSampleBuffer(
            dataBuffer: blockBuffer,
            formatDescription: format,
            sampleCount: count,
            timing: timing,
            sampleSizes: sizeLayout.constructorSizes,
            readinessTracker: readinessTracker
        )
        CMPropagateAttachments(self, destination: copy)
        copySampleAttachments(to: copy)
        return copy
    }

    private func requireValid() throws(CMSampleBufferError) {
        try state.withLock { state throws(CMSampleBufferError) in
            guard state.isValid else {
                throw .invalidated
            }
        }
    }

    private func currentReadiness()
        throws(CMSampleBufferError) -> CMSampleBufferDataReadiness
    {
        try requireValid()
        return readinessTracker?.readiness ?? .ready
    }

    private func requireReady() throws(CMSampleBufferError) {
        switch try currentReadiness() {
        case .ready:
            return
        case .notReady:
            throw .dataNotReady
        case .failed(let code):
            throw .dataFailed(code: code)
        }
    }

    private func validateSampleIndex(
        _ index: Int
    ) throws(CMSampleBufferError) {
        guard index >= 0, index < count else {
            throw .sampleIndexOutOfBounds(
                index: index,
                count: count
            )
        }
    }

    private func materializedSampleAttachmentStorages()
        -> [CMSampleAttachmentDictionaryStorage]
    {
        state.withLock { state in
            if let storages = state.sampleAttachmentStorages {
                return storages
            }
            var storages: [CMSampleAttachmentDictionaryStorage] = []
            storages.reserveCapacity(count)
            for _ in 0..<count {
                storages.append(CMSampleAttachmentDictionaryStorage())
            }
            state.sampleAttachmentStorages = storages
            return storages
        }
    }

    private func existingSampleAttachmentStorages()
        -> [CMSampleAttachmentDictionaryStorage]?
    {
        state.withLock { $0.sampleAttachmentStorages }
    }

    private func copySampleAttachments(
        to destination: borrowing CMBlockSampleBuffer
    ) {
        guard let sourceStorages = existingSampleAttachmentStorages() else {
            return
        }
        var copied: [CMSampleAttachmentDictionaryStorage] = []
        copied.reserveCapacity(sourceStorages.count)
        for storage in sourceStorages {
            copied.append(storage.copy())
        }
        destination.installSampleAttachmentStorages(copied)
    }

    private func installSampleAttachmentStorages(
        _ storages: [CMSampleAttachmentDictionaryStorage]
    ) {
        state.withLock { $0.sampleAttachmentStorages = storages }
    }

    private static func timingLayout(
        _ timing: [CMSampleTimingInfo],
        sampleCount: Int
    ) throws(CMSampleBufferError) -> CMBlockSampleTimingLayout {
        guard timing.isEmpty
                || timing.count == 1
                || timing.count == sampleCount
        else {
            throw .timingCountMismatch(
                expected: sampleCount,
                actual: timing.count
            )
        }
        if timing.isEmpty {
            return .invalid
        }
        if timing.count == sampleCount {
            for entry in timing {
                try validate(entry)
            }
            return .individual(timing)
        }

        let first = timing[0]
        try validate(first)
        if sampleCount > 1 {
            _ = try CMBlockSampleTimingLayout.uniform(first).timing(
                at: sampleCount - 1
            )
        }
        return .uniform(first)
    }

    private static func sizeLayout(
        _ sampleSizes: [Int],
        sampleCount: Int
    ) throws(CMSampleBufferError) -> CMBlockSampleSizeLayout {
        guard sampleSizes.isEmpty
                || sampleSizes.count == 1
                || sampleSizes.count == sampleCount
        else {
            throw .sampleSizeCountMismatch(
                sampleCount: sampleCount,
                sizeCount: sampleSizes.count
            )
        }
        guard !sampleSizes.contains(where: { $0 < 0 }) else {
            throw .sampleSizeOverflow
        }
        if sampleSizes.isEmpty {
            return .unavailable
        }
        if sampleSizes.count == 1 {
            let size = sampleSizes[0]
            guard size == 0 || sampleCount <= Int.max / size else {
                throw .sampleSizeOverflow
            }
            return .uniform(size)
        }
        var offsets = [Int]()
        offsets.reserveCapacity(sampleSizes.count + 1)
        offsets.append(0)
        var total = 0
        for size in sampleSizes {
            guard size <= Int.max - total else {
                throw .sampleSizeOverflow
            }
            total += size
            offsets.append(total)
        }
        return .individual(sizes: sampleSizes, offsets: offsets)
    }

    private static func totalSize(
        _ layout: CMBlockSampleSizeLayout,
        sampleCount: Int
    ) -> Int? {
        switch layout {
        case .unavailable:
            return nil
        case .uniform(let size):
            return size * sampleCount
        case .individual(_, let offsets):
            return offsets.last
        }
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
