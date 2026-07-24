public final class CMBlockBuffer: CMBlockBufferProtocol {
    public typealias CustomBlockDeallocator = (
        UnsafeMutableRawPointer,
        Int
    ) -> Void

    private let memoryLease: CMBlockBufferMemoryLease
    private let storageRange: Range<Int>

    public init(
        buffer: UnsafeMutableRawBufferPointer,
        deallocator: @escaping CustomBlockDeallocator,
        flags: Flags = []
    ) throws(CMBlockBufferError) {
        // FIXME(INCOMPLETE_IMPLEMENTATION): The production constructor currently
        // accepts one already-allocated contiguous segment and rejects every
        // allocation-policy flag. It must not accept these flags until
        // deferred allocation and explicit contiguous materialization preserve
        // their documented ownership and copy behavior.
        guard flags.isEmpty else {
            throw .unsupportedFlags(rawValue: flags.rawValue)
        }
        guard buffer.count > 0 else {
            throw .emptyBuffer
        }
        guard let baseAddress = buffer.baseAddress else {
            throw .storageUnavailable
        }

        memoryLease = CMBlockBufferMemoryLease(
            pointer: baseAddress,
            byteCount: buffer.count,
            deallocator: deallocator
        )
        storageRange = 0..<buffer.count
    }

    public init(referencing object: CMBlockBuffer) {
        memoryLease = object.memoryLease
        storageRange = object.storageRange
    }

    public var owner: CMBlockBuffer {
        self
    }

    public var startIndex: Int {
        storageRange.lowerBound
    }

    public var endIndex: Int {
        storageRange.upperBound
    }

    public var isEmpty: Bool {
        dataLength == 0
    }

    var isStorageContiguous: Bool {
        true
    }

    #if hasFeature(Embedded)
    public func withUnsafeMutableBytes<R>(
        atOffset offset: Int = 0,
        _ body: (UnsafeMutableRawBufferPointer) -> R
    ) throws(CMBlockBufferError) -> R {
        guard offset >= 0, offset <= dataLength else {
            throw .invalidRange(
                lowerBound: offset,
                upperBound: dataLength,
                validLowerBound: 0,
                validUpperBound: dataLength
            )
        }
        let requestedRange = offset..<dataLength
        let absoluteRange = try validatedAbsoluteRange(requestedRange)
        return withWriteBytes(in: absoluteRange, body)
    }
    #else
    public func withUnsafeMutableBytes<R>(
        atOffset offset: Int = 0,
        _ body: (UnsafeMutableRawBufferPointer) throws -> R
    ) throws -> R {
        guard offset >= 0, offset <= dataLength else {
            throw CMBlockBufferError.invalidRange(
                lowerBound: offset,
                upperBound: dataLength,
                validLowerBound: 0,
                validUpperBound: dataLength
            )
        }
        let requestedRange = offset..<dataLength
        let absoluteRange = try validatedAbsoluteRange(requestedRange)
        return try withWriteBytes(in: absoluteRange, body)
    }
    #endif

    func validatedSlice(
        _ bounds: Range<Int>,
        within validBounds: Range<Int>
    ) throws(CMBlockBufferError) -> Slice {
        guard bounds.lowerBound >= validBounds.lowerBound,
              bounds.upperBound <= validBounds.upperBound,
              bounds.lowerBound <= bounds.upperBound
        else {
            throw .invalidRange(
                lowerBound: bounds.lowerBound,
                upperBound: bounds.upperBound,
                validLowerBound: validBounds.lowerBound,
                validUpperBound: validBounds.upperBound
            )
        }
        return Slice(owner: self, bounds: bounds)
    }

    func preconditionedSlice(
        _ bounds: Range<Int>,
        within validBounds: Range<Int>
    ) -> Slice {
        precondition(
            bounds.lowerBound >= validBounds.lowerBound
                && bounds.upperBound <= validBounds.upperBound
                && bounds.lowerBound <= bounds.upperBound,
            "CMBlockBuffer slice is outside the represented byte range"
        )
        return Slice(owner: self, bounds: bounds)
    }

    #if hasFeature(Embedded)
    func withReadBytes<R>(
        in range: Range<Int>,
        _ body: (UnsafeRawBufferPointer) -> R
    ) -> R {
        memoryLease.withReadBytes(in: range, body)
    }

    func withWriteBytes<R>(
        in range: Range<Int>,
        _ body: (UnsafeMutableRawBufferPointer) -> R
    ) -> R {
        memoryLease.withWriteBytes(in: range, body)
    }
    #else
    func withReadBytes<R>(
        in range: Range<Int>,
        _ body: (UnsafeRawBufferPointer) throws -> R
    ) rethrows -> R {
        try memoryLease.withReadBytes(in: range, body)
    }

    func withWriteBytes<R>(
        in range: Range<Int>,
        _ body: (UnsafeMutableRawBufferPointer) throws -> R
    ) rethrows -> R {
        try memoryLease.withWriteBytes(in: range, body)
    }
    #endif

    private func validatedAbsoluteRange(
        _ relativeRange: Range<Int>
    ) throws(CMBlockBufferError) -> Range<Int> {
        guard relativeRange.lowerBound >= 0,
              relativeRange.upperBound <= dataLength,
              relativeRange.lowerBound <= relativeRange.upperBound
        else {
            throw .invalidRange(
                lowerBound: relativeRange.lowerBound,
                upperBound: relativeRange.upperBound,
                validLowerBound: 0,
                validUpperBound: dataLength
            )
        }

        return (startIndex + relativeRange.lowerBound)
            ..< (startIndex + relativeRange.upperBound)
    }
}
