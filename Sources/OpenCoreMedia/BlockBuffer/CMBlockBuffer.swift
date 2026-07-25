public final class CMBlockBuffer: CMBlockBufferProtocol {
    // FIXME(INCOMPLETE_IMPLEMENTATION): CMBlockBuffer currently has no
    // CMAttachmentBearerProtocol conformance, so attachment operations have no
    // callable path for block buffers and fail at compile time. Block-buffer
    // attachments must not be reported as supported until storage, propagation,
    // reference-copy behavior, and Apple differential tests are implemented.
    public typealias CustomBlockDeallocator = (
        UnsafeMutableRawPointer,
        Int
    ) -> Void
    public typealias CustomBlockAllocator = (
        Int
    ) -> UnsafeMutableRawPointer?

    private var segments: [CMBlockBufferSegment]
    private var storageLength: Int
    private static let eagerReservationLimit = 4_096
    private static let maximumCapacity =
        Int(exactly: UInt32.max) ?? Int.max

    public init(
        capacity: Int = 0,
        flags: Flags = []
    ) throws(CMBlockBufferError) {
        guard capacity >= 0, capacity <= Self.maximumCapacity else {
            throw .invalidCapacity(capacity)
        }
        try Self.validate(flags: flags, allowing: [])

        segments = []
        segments.reserveCapacity(
            min(capacity, Self.eagerReservationLimit)
        )
        storageLength = 0
    }

    public init(
        buffer: UnsafeMutableRawBufferPointer,
        deallocator: @escaping CustomBlockDeallocator,
        flags: Flags = []
    ) throws(CMBlockBufferError) {
        // FIXME(INCOMPLETE_IMPLEMENTATION): This constructor requires an
        // already-allocated memory block. The current call path supports
        // immediate external leases, segmented append, and explicit contiguous
        // materialization, but not allocator-backed deferred blocks. Deferred
        // flags must not report success until allocation and failure behavior
        // are implemented.
        try Self.validate(flags: flags, allowing: [.assureMemoryNow])
        guard buffer.count > 0 else {
            throw .emptyBuffer
        }
        guard let baseAddress = buffer.baseAddress else {
            throw .storageUnavailable
        }

        let lease = CMBlockBufferMemoryLease(
            pointer: baseAddress,
            byteCount: buffer.count,
            deallocator: deallocator
        )
        segments = [
            CMBlockBufferSegment(
                lease: lease,
                leaseRange: 0..<buffer.count
            )
        ]
        storageLength = buffer.count
    }

    public init<Reference: CMBlockBufferProtocol>(
        bufferReference: Reference,
        flags: Flags = []
    ) throws(CMBlockBufferError) {
        segments = []
        storageLength = 0
        try append(bufferReference: bufferReference, flags: flags)
    }

    public init(referencing object: CMBlockBuffer) {
        segments = object.segments
        storageLength = object.storageLength
    }

    public var owner: CMBlockBuffer {
        self
    }

    public var startIndex: Int {
        0
    }

    public var endIndex: Int {
        storageLength
    }

    public var isEmpty: Bool {
        dataLength == 0
    }

    public func append(
        buffer: UnsafeMutableRawBufferPointer,
        deallocator: @escaping CustomBlockDeallocator,
        flags: Flags = []
    ) throws(CMBlockBufferError) {
        try Self.validate(flags: flags, allowing: [.assureMemoryNow])
        guard buffer.count > 0 else {
            throw .emptyBuffer
        }
        guard let baseAddress = buffer.baseAddress else {
            throw .storageUnavailable
        }
        try validateAppendedLength(buffer.count)

        let lease = CMBlockBufferMemoryLease(
            pointer: baseAddress,
            byteCount: buffer.count,
            deallocator: deallocator
        )
        appendSegments([
            CMBlockBufferSegment(
                lease: lease,
                leaseRange: 0..<buffer.count
            )
        ])
        storageLength += buffer.count
    }

    public func append<Reference: CMBlockBufferProtocol>(
        bufferReference: Reference,
        flags: Flags = []
    ) throws(CMBlockBufferError) {
        try Self.validate(
            flags: flags,
            allowing: [
                .assureMemoryNow,
                .dontOptimizeDepth,
                .permitEmptyReference
            ]
        )

        let referencedRange = try bufferReference.owner.validatedProtocolRange(
            startIndex: bufferReference.startIndex,
            endIndex: bufferReference.endIndex
        )
        let referencedLength = referencedRange.count
        if referencedLength == 0 {
            guard flags.contains(.permitEmptyReference) else {
                throw .emptyBuffer
            }
            return
        }
        try validateAppendedLength(referencedLength)

        let referencedSegments = try bufferReference.owner.segmentViews(
            in: referencedRange
        )
        appendSegments(referencedSegments)
        storageLength += referencedLength
    }

    public func assureBlockMemory() throws(CMBlockBufferError) {
        guard !isEmpty else {
            throw .emptyBuffer
        }
    }

    /// Borrows the directly addressable bytes in the segment at `offset`.
    ///
    /// The buffer and every pointer derived from it are valid only during
    /// `body`. Returning or storing those pointers violates this API's
    /// ownership contract.
    public func withUnsafeMutableBytes<R>(
        atOffset offset: Int = 0,
        _ body: (UnsafeMutableRawBufferPointer) throws -> R
    ) throws -> R {
        guard offset >= 0, offset < dataLength else {
            throw CMBlockBufferError.invalidRange(
                lowerBound: offset,
                upperBound: offset,
                validLowerBound: 0,
                validUpperBound: dataLength
            )
        }
        guard let segment = segmentTail(at: offset) else {
            throw CMBlockBufferError.storageUnavailable
        }
        return try segment.lease.withWriteBytes(
            in: segment.leaseRange,
            body
        )
    }

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

    func withReadBytes<R>(
        in range: Range<Int>,
        _ body: (UnsafeRawBufferPointer) throws -> R
    ) throws -> R {
        let segment = try contiguousSegment(in: range)
        return try segment.lease.withReadBytes(
            in: segment.leaseRange,
            body
        )
    }

    func withWriteBytes<R>(
        in range: Range<Int>,
        _ body: (UnsafeMutableRawBufferPointer) throws -> R
    ) throws -> R {
        let segment = try contiguousSegment(in: range)
        return try segment.lease.withWriteBytes(
            in: segment.leaseRange,
            body
        )
    }

    func isStorageContiguous(
        startIndex: Int,
        endIndex: Int
    ) -> Bool {
        guard startIndex >= 0,
              endIndex >= startIndex,
              endIndex <= storageLength
        else {
            return false
        }
        let range = startIndex..<endIndex
        if range.isEmpty {
            return range.lowerBound < storageLength
                && segmentTail(at: range.lowerBound) != nil
        }
        return contiguousSegmentView(in: range) != nil
    }

    func copyBytes(
        in range: Range<Int>,
        to destination: UnsafeMutableRawBufferPointer
    ) throws(CMBlockBufferError) {
        let writtenDestination = UnsafeMutableRawBufferPointer(
            rebasing: destination[..<range.count]
        )
        let readOnlyDestination = UnsafeRawBufferPointer(writtenDestination)
        var overlapsStorage = false
        try forEachSegmentView(in: range) { view in
            if view.lease.overlaps(
                readOnlyDestination,
                in: view.leaseRange
            ) {
                overlapsStorage = true
            }
        }
        guard !overlapsStorage else {
            throw .overlappingMemory
        }
        var destinationOffset = 0

        try forEachSegmentView(in: range) { view in
            view.lease.withReadBytes(in: view.leaseRange) { source in
                let target = UnsafeMutableRawBufferPointer(
                    rebasing: destination[
                        destinationOffset..<(destinationOffset + source.count)
                    ]
                )
                target.copyMemory(from: source)
            }
            destinationOffset += view.count
        }
    }

    func replaceBytes(
        in range: Range<Int>,
        with source: UnsafeRawBufferPointer
    ) throws(CMBlockBufferError) {
        var overlapsStorage = false
        try forEachSegmentView(in: range) { view in
            if view.lease.overlaps(source, in: view.leaseRange) {
                overlapsStorage = true
            }
        }
        guard !overlapsStorage else {
            throw .overlappingMemory
        }
        var sourceOffset = 0

        try forEachSegmentView(in: range) { view in
            view.lease.withWriteBytes(in: view.leaseRange) { destination in
                let sourceView = UnsafeRawBufferPointer(
                    rebasing: source[
                        sourceOffset..<(sourceOffset + destination.count)
                    ]
                )
                destination.copyMemory(from: sourceView)
            }
            sourceOffset += view.count
        }
    }

    func fillBytes(
        in range: Range<Int>,
        with fillByte: UInt8
    ) throws(CMBlockBufferError) {
        try forEachSegmentView(in: range) { view in
            view.lease.withWriteBytes(in: view.leaseRange) { destination in
                _ = destination.initializeMemory(
                    as: UInt8.self,
                    repeating: fillByte
                )
            }
        }
    }

    func contiguousBuffer(
        in range: Range<Int>,
        allocator: @escaping CustomBlockAllocator,
        deallocator: @escaping CustomBlockDeallocator,
        flags: Flags
    ) throws(CMBlockBufferError) -> CMBlockBuffer {
        try Self.validate(
            flags: flags,
            allowing: [.assureMemoryNow, .alwaysCopyData]
        )
        guard !range.isEmpty else {
            if storageLength == 0 {
                throw .emptyBuffer
            }
            throw .invalidLength(0)
        }

        if !flags.contains(.alwaysCopyData),
           let segment = contiguousSegmentView(in: range)
        {
            return CMBlockBuffer(segments: [segment])
        }

        guard let pointer = allocator(range.count) else {
            throw .allocationFailed(length: range.count)
        }
        let destination = UnsafeMutableRawBufferPointer(
            start: pointer,
            count: range.count
        )

        do {
            try copyBytes(in: range, to: destination)
        } catch {
            deallocator(pointer, range.count)
            throw error
        }

        let lease = CMBlockBufferMemoryLease(
            pointer: pointer,
            byteCount: range.count,
            deallocator: deallocator
        )
        return CMBlockBuffer(segments: [
            CMBlockBufferSegment(
                lease: lease,
                leaseRange: 0..<range.count
            )
        ])
    }

    private init(segments: [CMBlockBufferSegment]) {
        self.segments = segments
        storageLength = segments.reduce(into: 0) { length, segment in
            length += segment.count
        }
    }

    private func validateAppendedLength(
        _ appendedLength: Int
    ) throws(CMBlockBufferError) {
        guard appendedLength <= Int.max - storageLength else {
            throw .lengthOverflow
        }
    }

    private func contiguousSegment(
        in range: Range<Int>
    ) throws(CMBlockBufferError) -> CMBlockBufferSegment {
        _ = try validatedStorageRange(range)
        guard let segment = contiguousSegmentView(in: range) else {
            throw .nonContiguousStorage
        }
        return segment
    }

    private func contiguousSegmentView(
        in range: Range<Int>
    ) -> CMBlockBufferSegment? {
        if range.isEmpty {
            return segmentTail(at: range.lowerBound).map { segment in
                CMBlockBufferSegment(
                    lease: segment.lease,
                    leaseRange:
                        segment.leaseRange.lowerBound
                        ..< segment.leaseRange.lowerBound
                )
            }
        }

        var logicalOffset = 0
        for segment in segments {
            let logicalUpperBound = logicalOffset + segment.count
            if range.lowerBound >= logicalOffset,
               range.upperBound <= logicalUpperBound
            {
                let leaseLowerBound =
                    segment.leaseRange.lowerBound
                    + (range.lowerBound - logicalOffset)
                return CMBlockBufferSegment(
                    lease: segment.lease,
                    leaseRange:
                        leaseLowerBound
                        ..< (leaseLowerBound + range.count)
                )
            }
            logicalOffset = logicalUpperBound
        }
        return nil
    }

    private func segmentTail(
        at offset: Int
    ) -> CMBlockBufferSegment? {
        guard offset >= 0, offset < storageLength else {
            return nil
        }

        var logicalOffset = 0
        for segment in segments {
            let logicalUpperBound = logicalOffset + segment.count
            if offset < logicalUpperBound {
                let leaseLowerBound =
                    segment.leaseRange.lowerBound
                    + (offset - logicalOffset)
                return CMBlockBufferSegment(
                    lease: segment.lease,
                    leaseRange:
                        leaseLowerBound..<segment.leaseRange.upperBound
                )
            }
            logicalOffset = logicalUpperBound
        }
        return nil
    }

    private func segmentViews(
        in range: Range<Int>
    ) throws(CMBlockBufferError) -> [CMBlockBufferSegment] {
        var result: [CMBlockBufferSegment] = []
        try forEachSegmentView(in: range) { view in
            result.append(view)
        }
        return result
    }

    private func forEachSegmentView(
        in range: Range<Int>,
        _ body: (CMBlockBufferSegment) -> Void
    ) throws(CMBlockBufferError) {
        _ = try validatedStorageRange(range)
        guard !range.isEmpty else {
            return
        }

        var logicalOffset = 0
        for segment in segments {
            let logicalUpperBound = logicalOffset + segment.count
            let overlapLowerBound = max(range.lowerBound, logicalOffset)
            let overlapUpperBound = min(range.upperBound, logicalUpperBound)

            if overlapLowerBound < overlapUpperBound {
                let leaseLowerBound =
                    segment.leaseRange.lowerBound
                    + (overlapLowerBound - logicalOffset)
                body(CMBlockBufferSegment(
                    lease: segment.lease,
                    leaseRange:
                        leaseLowerBound
                        ..< (
                            leaseLowerBound
                            + overlapUpperBound
                            - overlapLowerBound
                        )
                ))
            }
            logicalOffset = logicalUpperBound
            if logicalOffset >= range.upperBound {
                break
            }
        }
    }

    private func validatedStorageRange(
        _ range: Range<Int>
    ) throws(CMBlockBufferError) -> Range<Int> {
        guard range.lowerBound >= 0,
              range.upperBound <= storageLength,
              range.lowerBound <= range.upperBound
        else {
            throw .invalidRange(
                lowerBound: range.lowerBound,
                upperBound: range.upperBound,
                validLowerBound: 0,
                validUpperBound: storageLength
            )
        }
        return range
    }

    func validatedProtocolRange(
        startIndex: Int,
        endIndex: Int
    ) throws(CMBlockBufferError) -> Range<Int> {
        guard startIndex >= 0,
              endIndex >= startIndex,
              endIndex <= storageLength
        else {
            throw .invalidRange(
                lowerBound: startIndex,
                upperBound: endIndex,
                validLowerBound: 0,
                validUpperBound: storageLength
            )
        }
        return startIndex..<endIndex
    }

    private func appendSegments(
        _ appendedSegments: [CMBlockBufferSegment]
    ) {
        for segment in appendedSegments {
            if let last = segments.last,
               last.canMerge(with: segment)
            {
                segments[segments.count - 1] = last.merged(with: segment)
            } else {
                segments.append(segment)
            }
        }
    }

    private static func validate(
        flags: Flags,
        allowing allowedFlags: Flags
    ) throws(CMBlockBufferError) {
        let unsupportedFlags = flags.subtracting(allowedFlags)
        guard unsupportedFlags.isEmpty else {
            throw .unsupportedFlags(rawValue: unsupportedFlags.rawValue)
        }
    }
}
