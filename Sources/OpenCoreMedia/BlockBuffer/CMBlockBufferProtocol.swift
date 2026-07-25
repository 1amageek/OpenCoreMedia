/// A logical byte range retained by a `CMBlockBuffer` owner.
///
/// Conforming types must keep `startIndex...endIndex` within `owner` and must
/// not invert the indices. Throwing operations validate this invariant before
/// accessing storage.
public protocol CMBlockBufferProtocol: CMPlatformConcurrencyContract {
    var owner: CMBlockBuffer { get }
    var startIndex: Int { get }
    var endIndex: Int { get }
}

extension CMBlockBufferProtocol {
    /// Returns the represented owner range after validating the view.
    ///
    /// Throwing adapters should use this method instead of `dataLength` when
    /// the conforming value can originate outside this package.
    @_spi(OpenCoreMediaFoundation)
    public func validatedDataRange()
        throws(CMBlockBufferError) -> Range<Int>
    {
        try owner.validatedProtocolRange(
            startIndex: startIndex,
            endIndex: endIndex
        )
    }

    public var dataLength: Int {
        precondition(
            startIndex >= 0
                && endIndex >= startIndex
                && endIndex <= owner.endIndex,
            "CMBlockBufferProtocol indices must remain within the owner"
        )
        return endIndex - startIndex
    }

    public var isContiguous: Bool {
        owner.isStorageContiguous(
            startIndex: startIndex,
            endIndex: endIndex
        )
    }

    public func slice(
        _ bounds: Range<Int>
    ) throws(CMBlockBufferError) -> CMBlockBuffer.Slice {
        let validRange = try owner.validatedProtocolRange(
            startIndex: startIndex,
            endIndex: endIndex
        )
        return try owner.validatedSlice(
            bounds,
            within: validRange
        )
    }

    public subscript(bounds: Range<Int>) -> CMBlockBuffer.Slice {
        precondition(
            startIndex >= 0
                && endIndex >= startIndex
                && endIndex <= owner.endIndex,
            "CMBlockBufferProtocol indices must remain within the owner"
        )
        return owner.preconditionedSlice(
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

    /// Borrows this view's contiguous storage for the duration of `body`.
    ///
    /// The buffer and every pointer derived from it are valid only during
    /// `body`. Returning or storing those pointers violates this API's
    /// ownership contract.
    public func withContiguousStorage<R>(
        _ body: (UnsafeRawBufferPointer) throws -> R
    ) throws -> R {
        let range = try validatedDataRange()
        guard !range.isEmpty else {
            throw CMBlockBufferError.emptyBuffer
        }
        guard isContiguous else {
            throw CMBlockBufferError.nonContiguousStorage
        }
        return try owner.withReadBytes(
            in: range,
            body
        )
    }

    public func copyDataBytes(
        to destination: UnsafeMutableRawBufferPointer
    ) throws(CMBlockBufferError) {
        let range = try owner.validatedProtocolRange(
            startIndex: startIndex,
            endIndex: endIndex
        )
        guard !range.isEmpty else {
            throw .invalidLength(0)
        }
        guard destination.count >= range.count else {
            throw .destinationTooSmall(
                required: range.count,
                actual: destination.count
            )
        }

        try owner.copyBytes(
            in: range,
            to: destination
        )
    }

    public func replaceDataBytes(
        with sourceBytes: UnsafeRawBufferPointer
    ) throws(CMBlockBufferError) {
        let range = try owner.validatedProtocolRange(
            startIndex: startIndex,
            endIndex: endIndex
        )
        guard !sourceBytes.isEmpty else {
            throw .invalidLength(0)
        }
        guard sourceBytes.count <= range.count else {
            throw .sourceTooLarge(
                maximum: range.count,
                actual: sourceBytes.count
            )
        }

        try owner.replaceBytes(
            in: range.lowerBound..<(range.lowerBound + sourceBytes.count),
            with: sourceBytes
        )
    }

    public func fillDataBytes(
        with fillByte: UInt8
    ) throws(CMBlockBufferError) {
        let range = try owner.validatedProtocolRange(
            startIndex: startIndex,
            endIndex: endIndex
        )
        guard !owner.isEmpty else {
            throw .emptyBuffer
        }
        guard !range.isEmpty else {
            return
        }
        try owner.fillBytes(
            in: range,
            with: fillByte
        )
    }

    public func makeContiguous(
        allocator: @escaping CMBlockBuffer.CustomBlockAllocator,
        deallocator: @escaping CMBlockBuffer.CustomBlockDeallocator,
        flags: CMBlockBuffer.Flags = []
    ) throws(CMBlockBufferError) -> CMBlockBuffer {
        let range = try owner.validatedProtocolRange(
            startIndex: startIndex,
            endIndex: endIndex
        )
        return try owner.contiguousBuffer(
            in: range,
            allocator: allocator,
            deallocator: deallocator,
            flags: flags
        )
    }
}
