import Synchronization

public final class CMBlockBuffer:
    CMBlockBufferProtocol,
    CMAttachmentStorageBearerProtocol
{
    private final class Storage: Sendable {
        struct State: Sendable {
            var segments: [CMBlockBufferSegment]
            var length: Int
            var reservedLength: Int
        }

        let state: CMStateLock<State>
        let attachments: CMAttachmentBearerAttachments

        init(
            segments: [CMBlockBufferSegment],
            length: Int,
            attachments: CMAttachmentBearerAttachments =
                CMAttachmentBearerAttachments()
        ) {
            state = CMStateLock(State(
                segments: segments,
                length: length,
                reservedLength: 0
            ))
            self.attachments = attachments
        }
    }

    /// Releases a previously accepted memory block exactly once.
    ///
    /// The pointer and byte count are the allocator result and requested
    /// extent. The callback runs only after ownership was transferred by a
    /// successful initializer or append operation.
    public typealias CustomBlockDeallocator = @Sendable (
        UnsafeMutableRawPointer,
        Int
    ) -> Void

    /// Allocates at least the requested number of writable bytes.
    ///
    /// The returned pointer must remain valid until its paired deallocator is
    /// called and must have alignment suitable for raw byte access. Returning
    /// `nil` reports allocation failure without transferring ownership.
    public typealias CustomBlockAllocator = @Sendable (
        Int
    ) -> UnsafeMutableRawPointer?

    private let storage: Storage
    private var storageLength: Int {
        storage.state.withLock { $0.length }
    }
    public var attachments: CMAttachmentBearerAttachments {
        storage.attachments
    }
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

        var initialSegments: [CMBlockBufferSegment] = []
        initialSegments.reserveCapacity(
            min(capacity, Self.eagerReservationLimit)
        )
        storage = Storage(segments: initialSegments, length: 0)
    }

    /// Transfers the entire raw buffer to this block buffer on success.
    ///
    /// Validation failure leaves ownership with the caller. After success,
    /// the deallocator receives the original base address and full extent
    /// exactly once, even when only a subrange is represented.
    public convenience init(
        buffer: UnsafeMutableRawBufferPointer,
        deallocator: @escaping CustomBlockDeallocator,
        flags: Flags = []
    ) throws(CMBlockBufferError) {
        try self.init(
            buffer: buffer,
            offsetToData: 0,
            dataLength: buffer.count,
            deallocator: deallocator,
            flags: flags
        )
    }

    /// Transfers a raw block while representing only the selected range.
    ///
    /// Validation failure leaves ownership with the caller. After success,
    /// the deallocator receives the original base address and full extent
    /// exactly once.
    public init(
        buffer: UnsafeMutableRawBufferPointer,
        offsetToData: Int,
        dataLength: Int,
        deallocator: @escaping CustomBlockDeallocator,
        flags: Flags = []
    ) throws(CMBlockBufferError) {
        try Self.validate(flags: flags, allowing: [.assureMemoryNow])
        guard buffer.count > 0, dataLength > 0 else {
            throw .emptyBuffer
        }
        let dataRange = try Self.validatedBlockRange(
            offsetToData: offsetToData,
            dataLength: dataLength,
            blockLength: buffer.count
        )
        guard let baseAddress = buffer.baseAddress else {
            throw .storageUnavailable
        }

        let lease = CMBlockBufferMemoryLease(
            pointer: baseAddress,
            byteCount: buffer.count,
            deallocator: deallocator
        )
        storage = Storage(segments: [
            CMBlockBufferSegment(
                lease: lease,
                leaseRange: dataRange
            )
        ], length: dataLength)
    }

    /// Creates a block whose allocation can be deferred until first access.
    ///
    /// The allocator must return at least `blockLength` writable bytes.
    /// Ownership transfers only after a non-`nil` allocation result, and the
    /// paired deallocator then runs exactly once.
    public init(
        blockLength: Int,
        offsetToData: Int = 0,
        dataLength: Int? = nil,
        allocator: @escaping CustomBlockAllocator,
        deallocator: @escaping CustomBlockDeallocator,
        flags: Flags = []
    ) throws(CMBlockBufferError) {
        try Self.validate(flags: flags, allowing: [.assureMemoryNow])
        let representedLength = dataLength ?? blockLength
        let dataRange = try Self.validatedBlockRange(
            offsetToData: offsetToData,
            dataLength: representedLength,
            blockLength: blockLength
        )
        let lease = CMBlockBufferMemoryLease(
            deferredByteCount: blockLength,
            allocator: allocator,
            deallocator: deallocator
        )
        if flags.contains(.assureMemoryNow) {
            try lease.assureMemory()
        }
        storage = Storage(segments: [
            CMBlockBufferSegment(
                lease: lease,
                leaseRange: dataRange
            )
        ], length: representedLength)
    }

    public init<Reference: CMBlockBufferProtocol>(
        bufferReference: Reference,
        flags: Flags = []
    ) throws(CMBlockBufferError) {
        storage = Storage(segments: [], length: 0)
        try append(bufferReference: bufferReference, flags: flags)
    }

    /// Retains the same mutable block-buffer storage and attachments.
    ///
    /// Swift initializers cannot return the identical class object, but both
    /// wrappers observe later appends and attachment changes through the same
    /// shared storage, matching the observable Core Media retain contract.
    public init(referencing object: CMBlockBuffer) {
        storage = object.storage
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

    /// Appends a caller-owned block, transferring ownership only on success.
    public func append(
        buffer: UnsafeMutableRawBufferPointer,
        deallocator: @escaping CustomBlockDeallocator,
        flags: Flags = []
    ) throws(CMBlockBufferError) {
        try append(
            buffer: buffer,
            offsetToData: 0,
            dataLength: buffer.count,
            deallocator: deallocator,
            flags: flags
        )
    }

    /// Appends a represented subrange of a caller-owned memory block.
    ///
    /// Validation failure leaves ownership with the caller. On success, the
    /// full original block is retained and released exactly once.
    public func append(
        buffer: UnsafeMutableRawBufferPointer,
        offsetToData: Int,
        dataLength: Int,
        deallocator: @escaping CustomBlockDeallocator,
        flags: Flags = []
    ) throws(CMBlockBufferError) {
        try Self.validate(flags: flags, allowing: [.assureMemoryNow])
        guard buffer.count > 0, dataLength > 0 else {
            throw .emptyBuffer
        }
        let dataRange = try Self.validatedBlockRange(
            offsetToData: offsetToData,
            dataLength: dataLength,
            blockLength: buffer.count
        )
        guard let baseAddress = buffer.baseAddress else {
            throw .storageUnavailable
        }
        try commitAppend(length: dataLength) {
            let lease = CMBlockBufferMemoryLease(
                pointer: baseAddress,
                byteCount: buffer.count,
                deallocator: deallocator
            )
            return [
                CMBlockBufferSegment(
                    lease: lease,
                    leaseRange: dataRange
                )
            ]
        }
    }

    /// Appends a memory block whose allocation can be deferred.
    ///
    /// The allocator must return at least `blockLength` writable bytes.
    /// Failure before allocation leaves no deallocation obligation.
    public func append(
        blockLength: Int,
        offsetToData: Int = 0,
        dataLength: Int? = nil,
        allocator: @escaping CustomBlockAllocator,
        deallocator: @escaping CustomBlockDeallocator,
        flags: Flags = []
    ) throws(CMBlockBufferError) {
        try Self.validate(flags: flags, allowing: [.assureMemoryNow])
        let representedLength = dataLength ?? blockLength
        let dataRange = try Self.validatedBlockRange(
            offsetToData: offsetToData,
            dataLength: representedLength,
            blockLength: blockLength
        )
        try commitAppend(length: representedLength) {
            () throws(CMBlockBufferError) -> [CMBlockBufferSegment] in
            let lease = CMBlockBufferMemoryLease(
                deferredByteCount: blockLength,
                allocator: allocator,
                deallocator: deallocator
            )
            if flags.contains(.assureMemoryNow) {
                try lease.assureMemory()
            }
            return [
                CMBlockBufferSegment(
                    lease: lease,
                    leaseRange: dataRange
                )
            ]
        }
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
        let referencedSegments = try bufferReference.owner.segmentViews(
            in: referencedRange
        )
        try commitAppend(length: referencedLength) {
            () throws(CMBlockBufferError) -> [CMBlockBufferSegment] in
            if flags.contains(.assureMemoryNow) {
                for segment in referencedSegments {
                    try segment.lease.assureMemory()
                }
            }
            return referencedSegments
        }
    }

    public func assureBlockMemory() throws(CMBlockBufferError) {
        guard !isEmpty else {
            throw .emptyBuffer
        }
        for segment in storageSnapshot().segments {
            try segment.lease.assureMemory()
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
        let snapshot = storageSnapshot()
        guard startIndex >= 0,
              endIndex >= startIndex,
              endIndex <= snapshot.length
        else {
            return false
        }
        let range = startIndex..<endIndex
        if range.isEmpty {
            return range.lowerBound < snapshot.length
                && Self.segmentTail(
                    at: range.lowerBound,
                    in: snapshot
                ) != nil
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
        try forEachSegmentView(in: range) {
            view throws(CMBlockBufferError) in
            if try view.lease.overlaps(
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

        try forEachSegmentView(in: range) {
            view throws(CMBlockBufferError) in
            let target = UnsafeMutableRawBufferPointer(
                rebasing: destination[
                    destinationOffset..<(destinationOffset + view.count)
                ]
            )
            try view.lease.copyBytes(
                in: view.leaseRange,
                to: target
            )
            destinationOffset += view.count
        }
    }

    func replaceBytes(
        in range: Range<Int>,
        with source: UnsafeRawBufferPointer
    ) throws(CMBlockBufferError) {
        var overlapsStorage = false
        try forEachSegmentView(in: range) {
            view throws(CMBlockBufferError) in
            if try view.lease.overlaps(source, in: view.leaseRange) {
                overlapsStorage = true
            }
        }
        guard !overlapsStorage else {
            throw .overlappingMemory
        }
        var sourceOffset = 0

        try forEachSegmentView(in: range) {
            view throws(CMBlockBufferError) in
            let sourceView = UnsafeRawBufferPointer(
                rebasing: source[
                    sourceOffset..<(sourceOffset + view.count)
                ]
            )
            try view.lease.replaceBytes(
                in: view.leaseRange,
                with: sourceView
            )
            sourceOffset += view.count
        }
    }

    func fillBytes(
        in range: Range<Int>,
        with fillByte: UInt8
    ) throws(CMBlockBufferError) {
        try forEachSegmentView(in: range) {
            view throws(CMBlockBufferError) in
            try view.lease.assureMemory()
        }
        try forEachSegmentView(in: range) {
            view throws(CMBlockBufferError) in
            try view.lease.fillBytes(
                in: view.leaseRange,
                with: fillByte
            )
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
            if flags.contains(.assureMemoryNow) {
                try segment.lease.assureMemory()
            }
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
        let length = segments.reduce(into: 0) { length, segment in
            length += segment.count
        }
        storage = Storage(segments: segments, length: length)
    }

    private func storageSnapshot() -> Storage.State {
        storage.state.withLock { $0 }
    }

    private func commitAppend(
        length: Int,
        segments makeSegments: () throws(CMBlockBufferError)
            -> [CMBlockBufferSegment]
    ) throws(CMBlockBufferError) {
        try storage.state.withLock {
            state throws(CMBlockBufferError) in
            guard length <= Int.max - state.length,
                  state.reservedLength
                    <= Int.max - state.length - length
            else {
                throw .lengthOverflow
            }
            state.reservedLength += length
        }
        let appendedSegments: [CMBlockBufferSegment]
        do {
            appendedSegments = try makeSegments()
        } catch {
            storage.state.withLock { $0.reservedLength -= length }
            throw error
        }
        storage.state.withLock {
            state in
            state.reservedLength -= length
            Self.appendSegments(
                appendedSegments,
                to: &state.segments
            )
            state.length += length
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
        let snapshot = storageSnapshot()
        if range.isEmpty {
            return Self.segmentTail(
                at: range.lowerBound,
                in: snapshot
            ).map { segment in
                CMBlockBufferSegment(
                    lease: segment.lease,
                    leaseRange:
                        segment.leaseRange.lowerBound
                        ..< segment.leaseRange.lowerBound
                )
            }
        }

        var logicalOffset = 0
        for segment in snapshot.segments {
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
        Self.segmentTail(at: offset, in: storageSnapshot())
    }

    private static func segmentTail(
        at offset: Int,
        in snapshot: Storage.State
    ) -> CMBlockBufferSegment? {
        guard offset >= 0, offset < snapshot.length else {
            return nil
        }

        var logicalOffset = 0
        for segment in snapshot.segments {
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
        _ body: (CMBlockBufferSegment) throws(CMBlockBufferError) -> Void
    ) throws(CMBlockBufferError) {
        let snapshot = storageSnapshot()
        _ = try validatedStorageRange(range, in: snapshot)
        guard !range.isEmpty else {
            return
        }

        var logicalOffset = 0
        for segment in snapshot.segments {
            let logicalUpperBound = logicalOffset + segment.count
            let overlapLowerBound = max(range.lowerBound, logicalOffset)
            let overlapUpperBound = min(range.upperBound, logicalUpperBound)

            if overlapLowerBound < overlapUpperBound {
                let leaseLowerBound =
                    segment.leaseRange.lowerBound
                    + (overlapLowerBound - logicalOffset)
                try body(CMBlockBufferSegment(
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
        try validatedStorageRange(range, in: storageSnapshot())
    }

    private func validatedStorageRange(
        _ range: Range<Int>,
        in snapshot: Storage.State
    ) throws(CMBlockBufferError) -> Range<Int> {
        guard range.lowerBound >= 0,
              range.upperBound <= snapshot.length,
              range.lowerBound <= range.upperBound
        else {
            throw .invalidRange(
                lowerBound: range.lowerBound,
                upperBound: range.upperBound,
                validLowerBound: 0,
                validUpperBound: snapshot.length
            )
        }
        return range
    }

    func validatedProtocolRange(
        startIndex: Int,
        endIndex: Int
    ) throws(CMBlockBufferError) -> Range<Int> {
        let snapshot = storageSnapshot()
        guard startIndex >= 0,
              endIndex >= startIndex,
              endIndex <= snapshot.length
        else {
            throw .invalidRange(
                lowerBound: startIndex,
                upperBound: endIndex,
                validLowerBound: 0,
                validUpperBound: snapshot.length
            )
        }
        return startIndex..<endIndex
    }

    private static func appendSegments(
        _ appendedSegments: [CMBlockBufferSegment],
        to segments: inout [CMBlockBufferSegment]
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

    private static func validatedBlockRange(
        offsetToData: Int,
        dataLength: Int,
        blockLength: Int
    ) throws(CMBlockBufferError) -> Range<Int> {
        guard blockLength > 0,
              offsetToData >= 0,
              dataLength > 0,
              offsetToData <= blockLength,
              dataLength <= blockLength - offsetToData
        else {
            throw .invalidBlockRange(
                offsetToData: offsetToData,
                dataLength: dataLength,
                blockLength: blockLength
            )
        }
        return offsetToData..<(offsetToData + dataLength)
    }
}
