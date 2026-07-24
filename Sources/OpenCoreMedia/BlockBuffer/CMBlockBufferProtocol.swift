public protocol CMBlockBufferProtocol {
    var owner: CMBlockBuffer { get }
    var startIndex: Int { get }
    var endIndex: Int { get }
}

extension CMBlockBufferProtocol {
    public var dataLength: Int {
        endIndex - startIndex
    }

    public var isContiguous: Bool {
        owner.isStorageContiguous
    }

    public func slice(
        _ bounds: Range<Int>
    ) throws(CMBlockBufferError) -> CMBlockBuffer.Slice {
        try owner.validatedSlice(
            bounds,
            within: startIndex..<endIndex
        )
    }

    public subscript(bounds: Range<Int>) -> CMBlockBuffer.Slice {
        owner.preconditionedSlice(
            bounds,
            within: startIndex..<endIndex
        )
    }

    public subscript(bounds: ClosedRange<Int>) -> CMBlockBuffer.Slice {
        precondition(
            bounds.upperBound < Int.max,
            "CMBlockBuffer closed range cannot end at Int.max"
        )
        return self[bounds.lowerBound..<(bounds.upperBound + 1)]
    }

    public subscript(
        bounds: PartialRangeUpTo<Int>
    ) -> CMBlockBuffer.Slice {
        self[startIndex..<bounds.upperBound]
    }

    public subscript(
        bounds: PartialRangeThrough<Int>
    ) -> CMBlockBuffer.Slice {
        precondition(
            bounds.upperBound < Int.max,
            "CMBlockBuffer partial range cannot end at Int.max"
        )
        return self[startIndex..<(bounds.upperBound + 1)]
    }

    public subscript(
        bounds: PartialRangeFrom<Int>
    ) -> CMBlockBuffer.Slice {
        self[bounds.lowerBound..<endIndex]
    }

    public subscript(bounds: UnboundedRange) -> CMBlockBuffer.Slice {
        self[startIndex..<endIndex]
    }

    #if hasFeature(Embedded)
    public func withContiguousStorage<R>(
        _ body: (UnsafeRawBufferPointer) -> R
    ) throws(CMBlockBufferError) -> R {
        guard isContiguous else {
            throw .nonContiguousStorage
        }
        return owner.withReadBytes(
            in: startIndex..<endIndex,
            body
        )
    }
    #else
    public func withContiguousStorage<R>(
        _ body: (UnsafeRawBufferPointer) throws -> R
    ) throws -> R {
        guard isContiguous else {
            throw CMBlockBufferError.nonContiguousStorage
        }
        return try owner.withReadBytes(
            in: startIndex..<endIndex,
            body
        )
    }
    #endif

    public func copyDataBytes(
        to destination: UnsafeMutableRawBufferPointer
    ) throws(CMBlockBufferError) {
        guard destination.count >= dataLength else {
            throw .destinationTooSmall(
                required: dataLength,
                actual: destination.count
            )
        }

        owner.withReadBytes(in: startIndex..<endIndex) { source in
            let target = UnsafeMutableRawBufferPointer(
                rebasing: destination[..<dataLength]
            )
            target.copyMemory(from: source)
        }
    }

    public func replaceDataBytes(
        with sourceBytes: UnsafeRawBufferPointer
    ) throws(CMBlockBufferError) {
        guard sourceBytes.count <= dataLength else {
            throw .sourceTooLarge(
                maximum: dataLength,
                actual: sourceBytes.count
            )
        }

        owner.withWriteBytes(
            in: startIndex..<(startIndex + sourceBytes.count)
        ) { destination in
            destination.copyMemory(from: sourceBytes)
        }
    }

    public func fillDataBytes(with fillByte: UInt8) {
        owner.withWriteBytes(in: startIndex..<endIndex) { destination in
            _ = destination.initializeMemory(
                as: UInt8.self,
                repeating: fillByte
            )
        }
    }
}
