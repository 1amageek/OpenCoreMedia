import OpenCoreMedia
import Testing

@Suite("CMBlockBuffer smoke")
struct CMBlockBufferSmokeTests {
    @Test("External storage is borrowed without copying")
    func zeroCopyBorrow() throws {
        let pointer = UnsafeMutableRawPointer.allocate(
            byteCount: 8,
            alignment: 8
        )
        pointer.initializeMemory(as: UInt8.self, repeating: 0, count: 8)

        let buffer = try CMBlockBuffer(
            buffer: UnsafeMutableRawBufferPointer(
                start: pointer,
                count: 8
            ),
            deallocator: { releasedPointer, _ in
                releasedPointer.deallocate()
            }
        )

        #expect(buffer.dataLength == 8)
        #expect(buffer.isContiguous)
        try buffer.withContiguousStorage { bytes in
            #expect(bytes.baseAddress == UnsafeRawPointer(pointer))
        }

        try buffer.withUnsafeMutableBytes(atOffset: 2) { bytes in
            #expect(bytes.baseAddress == pointer.advanced(by: 2))
            #expect(bytes.count == 6)
            bytes[0] = 37
        }

        #expect(
            pointer.load(fromByteOffset: 2, as: UInt8.self) == 37
        )
    }

    @Test("References and slices retain one external memory lease")
    func lifetime() throws {
        let releaseCounter = BlockReleaseCounter()
        var retainedSlice: CMBlockBuffer.Slice?

        do {
            let pointer = UnsafeMutableRawPointer.allocate(
                byteCount: 8,
                alignment: 8
            )
            let buffer = try CMBlockBuffer(
                buffer: UnsafeMutableRawBufferPointer(
                    start: pointer,
                    count: 8
                ),
                deallocator: { releasedPointer, length in
                    releaseCounter.record(length: length)
                    releasedPointer.deallocate()
                }
            )
            let reference = CMBlockBuffer(referencing: buffer)
            retainedSlice = try reference.slice(2..<6)

            #expect(retainedSlice?.owner === reference)
            #expect(retainedSlice?.startIndex == 2)
            #expect(retainedSlice?.endIndex == 6)
            #expect(releaseCounter.count == 0)
        }

        #expect(releaseCounter.count == 0)
        retainedSlice = nil
        #expect(releaseCounter.count == 1)
        #expect(releaseCounter.releasedLength == 8)
    }

    @Test("Range errors are typed while valid subscripts match Apple usage")
    func rangeValidation() throws {
        let fixture = try makeBuffer(length: 8)
        let slice = fixture.buffer[2..<6]
        let nested = slice[3..<5]

        #expect(slice.dataLength == 4)
        #expect(nested.dataLength == 2)
        #expect(nested.owner === fixture.buffer)
        #expect(fixture.buffer[..<2].dataLength == 2)
        #expect(fixture.buffer[6...].dataLength == 2)
        #expect(fixture.buffer[2...4].dataLength == 3)
        #expect(fixture.buffer[...].dataLength == 8)

        #expect(throws: CMBlockBufferError.invalidRange(
            lowerBound: 1,
            upperBound: 7,
            validLowerBound: 2,
            validUpperBound: 6
        )) {
            _ = try slice.slice(1..<7)
        }

        #expect(throws: CMBlockBufferError.invalidRange(
            lowerBound: 9,
            upperBound: 9,
            validLowerBound: 0,
            validUpperBound: 8
        )) {
            try fixture.buffer.withUnsafeMutableBytes(
                atOffset: 9
            ) { _ in }
        }
    }

    @Test("Borrow closures propagate their own errors")
    func throwingBorrow() throws {
        let fixture = try makeBuffer(length: 8)

        #expect(throws: CMBlockBufferBorrowTestError.expected) {
            try fixture.buffer.withContiguousStorage { _ -> Void in
                throw CMBlockBufferBorrowTestError.expected
            }
        }
    }

    @Test("Explicit copy replace and fill operations expose copy boundaries")
    func explicitByteOperations() throws {
        let fixture = try makeBuffer(length: 8)
        try fixture.buffer.withUnsafeMutableBytes { bytes in
            for index in bytes.indices {
                bytes[index] = UInt8(index)
            }
        }

        let slice = fixture.buffer[2..<6]
        let copyPointer = UnsafeMutableRawPointer.allocate(
            byteCount: 6,
            alignment: 8
        )
        defer {
            copyPointer.deallocate()
        }
        copyPointer.initializeMemory(
            as: UInt8.self,
            repeating: 255,
            count: 6
        )
        try slice.copyDataBytes(
            to: UnsafeMutableRawBufferPointer(
                start: copyPointer,
                count: 6
            )
        )

        #expect(copyPointer.load(as: UInt8.self) == 2)
        #expect(
            copyPointer.load(fromByteOffset: 3, as: UInt8.self) == 5
        )
        #expect(
            copyPointer.load(fromByteOffset: 4, as: UInt8.self) == 255
        )

        try slice.fillDataBytes(with: 7)
        try slice.withContiguousStorage { bytes in
            #expect(bytes[0] == 7)
            #expect(bytes[3] == 7)
        }

        let sourcePointer = UnsafeMutableRawPointer.allocate(
            byteCount: 2,
            alignment: 8
        )
        defer {
            sourcePointer.deallocate()
        }
        sourcePointer.initializeMemory(
            as: UInt8.self,
            repeating: 19,
            count: 2
        )
        try slice.replaceDataBytes(
            with: UnsafeRawBufferPointer(
                start: sourcePointer,
                count: 2
            )
        )
        try slice.withContiguousStorage { bytes in
            #expect(bytes[0] == 19)
            #expect(bytes[1] == 19)
            #expect(bytes[2] == 7)
        }

        let smallDestination = UnsafeMutableRawPointer.allocate(
            byteCount: 2,
            alignment: 8
        )
        defer {
            smallDestination.deallocate()
        }
        #expect(throws: CMBlockBufferError.destinationTooSmall(
            required: 4,
            actual: 2
        )) {
            try slice.copyDataBytes(
                to: UnsafeMutableRawBufferPointer(
                    start: smallDestination,
                    count: 2
                )
            )
        }
    }

    @Test("Unsupported construction never silently changes storage policy")
    func constructionFailures() {
        #expect(throws: CMBlockBufferError.emptyBuffer) {
            _ = try CMBlockBuffer(
                buffer: UnsafeMutableRawBufferPointer(
                    start: nil,
                    count: 0
                ),
                deallocator: { _, _ in }
            )
        }

        let pointer = UnsafeMutableRawPointer.allocate(
            byteCount: 1,
            alignment: 1
        )
        defer {
            pointer.deallocate()
        }
        #expect(throws: CMBlockBufferError.unsupportedFlags(
            rawValue: CMBlockBuffer.Flags.alwaysCopyData.rawValue
        )) {
            _ = try CMBlockBuffer(
                buffer: UnsafeMutableRawBufferPointer(
                    start: pointer,
                    count: 1
                ),
                deallocator: { _, _ in },
                flags: .alwaysCopyData
            )
        }

        #expect(throws: CMBlockBufferError.invalidCapacity(Int.max)) {
            _ = try CMBlockBuffer(capacity: Int.max)
        }
    }

    @Test("Segmented append preserves leases and crosses segment boundaries")
    func segmentedAppend() throws {
        let first = try makeBuffer(length: 4)
        try first.buffer.withUnsafeMutableBytes { bytes in
            for index in bytes.indices {
                bytes[index] = UInt8(index)
            }
        }

        let secondPointer = UnsafeMutableRawPointer.allocate(
            byteCount: 4,
            alignment: 8
        )
        for index in 0..<4 {
            secondPointer.storeBytes(
                of: UInt8(index + 4),
                toByteOffset: index,
                as: UInt8.self
            )
        }
        let secondReleaseCounter = BlockReleaseCounter()
        try first.buffer.append(
            buffer: UnsafeMutableRawBufferPointer(
                start: secondPointer,
                count: 4
            ),
            deallocator: { pointer, length in
                secondReleaseCounter.record(length: length)
                pointer.deallocate()
            }
        )

        #expect(first.buffer.dataLength == 8)
        #expect(!first.buffer.isContiguous)
        #expect(throws: CMBlockBufferError.nonContiguousStorage) {
            try first.buffer.withContiguousStorage { _ in }
        }
        try first.buffer.withUnsafeMutableBytes { bytes in
            #expect(bytes.baseAddress == first.pointer)
            #expect(bytes.count == 4)
        }
        try first.buffer.withUnsafeMutableBytes(atOffset: 2) { bytes in
            #expect(bytes.baseAddress == first.pointer.advanced(by: 2))
            #expect(bytes.count == 2)
        }
        try first.buffer.withUnsafeMutableBytes(atOffset: 4) { bytes in
            #expect(bytes.baseAddress == secondPointer)
            #expect(bytes.count == 4)
        }
        #expect(throws: CMBlockBufferError.invalidRange(
            lowerBound: 8,
            upperBound: 8,
            validLowerBound: 0,
            validUpperBound: 8
        )) {
            try first.buffer.withUnsafeMutableBytes(atOffset: 8) { _ in }
        }

        let destination = UnsafeMutableRawPointer.allocate(
            byteCount: 8,
            alignment: 8
        )
        defer {
            destination.deallocate()
        }
        try first.buffer.copyDataBytes(
            to: UnsafeMutableRawBufferPointer(
                start: destination,
                count: 8
            )
        )
        for index in 0..<8 {
            #expect(
                destination.load(
                    fromByteOffset: index,
                    as: UInt8.self
                ) == UInt8(index)
            )
        }

        let crossSegmentSlice = first.buffer[2..<6]
        #expect(!crossSegmentSlice.isContiguous)
        try crossSegmentSlice.fillDataBytes(with: 9)
        try first.buffer.copyDataBytes(
            to: UnsafeMutableRawBufferPointer(
                start: destination,
                count: 8
            )
        )
        let expectedAfterFill: [UInt8] = [0, 1, 9, 9, 9, 9, 6, 7]
        for index in expectedAfterFill.indices {
            #expect(
                destination.load(
                    fromByteOffset: index,
                    as: UInt8.self
                ) == expectedAfterFill[index]
            )
        }

        let replacement = UnsafeMutableRawPointer.allocate(
            byteCount: 4,
            alignment: 8
        )
        defer {
            replacement.deallocate()
        }
        for index in 0..<4 {
            replacement.storeBytes(
                of: UInt8(index + 20),
                toByteOffset: index,
                as: UInt8.self
            )
        }
        try crossSegmentSlice.replaceDataBytes(
            with: UnsafeRawBufferPointer(
                start: replacement,
                count: 4
            )
        )
        try first.buffer.copyDataBytes(
            to: UnsafeMutableRawBufferPointer(
                start: destination,
                count: 8
            )
        )
        let expectedAfterReplace: [UInt8] =
            [0, 1, 20, 21, 22, 23, 6, 7]
        for index in expectedAfterReplace.indices {
            #expect(
                destination.load(
                    fromByteOffset: index,
                    as: UInt8.self
                ) == expectedAfterReplace[index]
            )
        }

        #expect(first.releaseCounter.count == 0)
        #expect(secondReleaseCounter.count == 0)
    }

    @Test("Every appended lease releases exactly once after references die")
    func segmentedLifetime() throws {
        let firstReleaseCounter = BlockReleaseCounter()
        let secondReleaseCounter = BlockReleaseCounter()
        var retainedReference: CMBlockBuffer?

        do {
            let firstPointer = UnsafeMutableRawPointer.allocate(
                byteCount: 4,
                alignment: 8
            )
            let buffer = try CMBlockBuffer(
                buffer: UnsafeMutableRawBufferPointer(
                    start: firstPointer,
                    count: 4
                ),
                deallocator: { pointer, length in
                    firstReleaseCounter.record(length: length)
                    pointer.deallocate()
                }
            )
            let secondPointer = UnsafeMutableRawPointer.allocate(
                byteCount: 4,
                alignment: 8
            )
            try buffer.append(
                buffer: UnsafeMutableRawBufferPointer(
                    start: secondPointer,
                    count: 4
                ),
                deallocator: { pointer, length in
                    secondReleaseCounter.record(length: length)
                    pointer.deallocate()
                }
            )
            retainedReference = CMBlockBuffer(referencing: buffer)
        }

        #expect(retainedReference?.dataLength == 8)
        #expect(firstReleaseCounter.count == 0)
        #expect(secondReleaseCounter.count == 0)
        retainedReference = nil
        #expect(firstReleaseCounter.count == 1)
        #expect(secondReleaseCounter.count == 1)
        #expect(firstReleaseCounter.releasedLength == 4)
        #expect(secondReleaseCounter.releasedLength == 4)
    }

    @Test("Buffer references share payload without following later appends")
    func bufferReferences() throws {
        let source = try makeBuffer(length: 6)
        try source.buffer.withUnsafeMutableBytes { bytes in
            for index in bytes.indices {
                bytes[index] = UInt8(index + 10)
            }
        }
        let referencedSlice = source.buffer[1..<5]
        let reference = try CMBlockBuffer(
            bufferReference: referencedSlice,
            flags: [.assureMemoryNow, .dontOptimizeDepth]
        )

        #expect(reference.dataLength == 4)
        #expect(reference.isContiguous)
        try reference.withContiguousStorage { bytes in
            #expect(
                bytes.baseAddress
                    == UnsafeRawPointer(source.pointer.advanced(by: 1))
            )
        }

        let appended = try makeBuffer(length: 2)
        try appended.buffer.append(
            bufferReference: referencedSlice,
            flags: .dontOptimizeDepth
        )
        #expect(appended.buffer.dataLength == 6)
        #expect(!appended.buffer.isContiguous)

        try source.buffer.withUnsafeMutableBytes(atOffset: 2) { bytes in
            bytes[0] = 77
        }
        let copied = UnsafeMutableRawPointer.allocate(
            byteCount: 6,
            alignment: 8
        )
        defer {
            copied.deallocate()
        }
        try appended.buffer.copyDataBytes(
            to: UnsafeMutableRawBufferPointer(
                start: copied,
                count: 6
            )
        )
        #expect(
            copied.load(fromByteOffset: 3, as: UInt8.self) == 77
        )

        let later = UnsafeMutableRawPointer.allocate(
            byteCount: 1,
            alignment: 1
        )
        later.storeBytes(of: UInt8(99), as: UInt8.self)
        try source.buffer.append(
            buffer: UnsafeMutableRawBufferPointer(
                start: later,
                count: 1
            ),
            deallocator: { pointer, _ in
                pointer.deallocate()
            }
        )
        #expect(source.buffer.dataLength == 7)
        #expect(reference.dataLength == 4)
        #expect(appended.buffer.dataLength == 6)
    }

    @Test("Contiguous materialization copies only when required")
    func contiguousMaterialization() throws {
        let source = try makeBuffer(length: 4)
        let appendedPointer = UnsafeMutableRawPointer.allocate(
            byteCount: 4,
            alignment: 8
        )
        appendedPointer.initializeMemory(
            as: UInt8.self,
            repeating: 2,
            count: 4
        )
        try source.buffer.append(
            buffer: UnsafeMutableRawBufferPointer(
                start: appendedPointer,
                count: 4
            ),
            deallocator: { pointer, _ in
                pointer.deallocate()
            }
        )

        let allocations = BlockAllocationCounter()
        var materialized: CMBlockBuffer? = try source.buffer.makeContiguous(
            allocator: { length in
                allocations.allocate(length: length)
            },
            deallocator: { pointer, length in
                allocations.release(pointer: pointer, length: length)
            }
        )
        #expect(allocations.allocationCount == 1)
        #expect(materialized?.isContiguous == true)

        source.pointer.storeBytes(of: UInt8(91), as: UInt8.self)
        try materialized?.withContiguousStorage { bytes in
            #expect(bytes[0] == 0)
            #expect(bytes[4] == 2)
        }
        materialized = nil
        #expect(allocations.releaseCount == 1)

        let contiguousSource = try makeBuffer(length: 4)
        for index in 0..<4 {
            contiguousSource.pointer.storeBytes(
                of: UInt8(index + 10),
                toByteOffset: index,
                as: UInt8.self
            )
        }
        let shared = try contiguousSource.buffer.makeContiguous(
            allocator: { length in
                allocations.allocate(length: length)
            },
            deallocator: { pointer, length in
                allocations.release(pointer: pointer, length: length)
            }
        )
        #expect(allocations.allocationCount == 1)
        try shared.withContiguousStorage { bytes in
            #expect(
                bytes.baseAddress
                    == UnsafeRawPointer(contiguousSource.pointer)
            )
        }

        var forcedCopy: CMBlockBuffer? =
            try contiguousSource.buffer.makeContiguous(
                allocator: { length in
                    allocations.allocate(length: length)
                },
                deallocator: { pointer, length in
                    allocations.release(pointer: pointer, length: length)
                },
                flags: .alwaysCopyData
            )
        #expect(allocations.allocationCount == 2)
        try forcedCopy?.withContiguousStorage { bytes in
            #expect(
                bytes.baseAddress
                    != UnsafeRawPointer(contiguousSource.pointer)
            )
            #expect(Array(bytes) == [10, 11, 12, 13])
        }
        contiguousSource.pointer.storeBytes(
            of: UInt8(99),
            as: UInt8.self
        )
        try forcedCopy?.withContiguousStorage { bytes in
            #expect(bytes[0] == 10)
        }
        forcedCopy = nil
        #expect(allocations.releaseCount == 2)
    }

    @Test("Slice materialization is limited to the represented range")
    func sliceMaterialization() throws {
        let source = try makeBuffer(length: 4)
        for index in 0..<4 {
            source.pointer.storeBytes(
                of: UInt8(index),
                toByteOffset: index,
                as: UInt8.self
            )
        }
        let appendedPointer = UnsafeMutableRawPointer.allocate(
            byteCount: 4,
            alignment: 4
        )
        for index in 0..<4 {
            appendedPointer.storeBytes(
                of: UInt8(index + 4),
                toByteOffset: index,
                as: UInt8.self
            )
        }
        try source.buffer.append(
            buffer: UnsafeMutableRawBufferPointer(
                start: appendedPointer,
                count: 4
            ),
            deallocator: { pointer, _ in
                pointer.deallocate()
            }
        )

        let allocations = BlockAllocationCounter()
        let shared = try source.buffer[1..<3].makeContiguous(
            allocator: { length in
                allocations.allocate(length: length)
            },
            deallocator: { pointer, length in
                allocations.release(pointer: pointer, length: length)
            }
        )
        #expect(allocations.allocationCount == 0)
        try shared.withContiguousStorage { bytes in
            #expect(
                bytes.baseAddress
                    == UnsafeRawPointer(source.pointer.advanced(by: 1))
            )
            #expect(bytes.count == 2)
        }

        var copied: CMBlockBuffer? = try source.buffer[2..<6].makeContiguous(
            allocator: { length in
                allocations.allocate(length: length)
            },
            deallocator: { pointer, length in
                allocations.release(pointer: pointer, length: length)
            }
        )
        #expect(allocations.allocationCount == 1)
        #expect(copied?.dataLength == 4)
        try copied?.withContiguousStorage { bytes in
            #expect(Array(bytes) == [2, 3, 4, 5])
        }
        copied = nil
        #expect(allocations.releaseCount == 1)
    }

    @Test("Empty and allocation failures remain explicit")
    func segmentedFailures() throws {
        let empty = try CMBlockBuffer(capacity: 2)
        #expect(empty.isEmpty)
        #expect(empty.dataLength == 0)
        #expect(!empty.isContiguous)
        #expect(throws: CMBlockBufferError.emptyBuffer) {
            try empty.assureBlockMemory()
        }
        #expect(throws: CMBlockBufferError.emptyBuffer) {
            _ = try CMBlockBuffer(bufferReference: empty)
        }
        #expect(throws: CMBlockBufferError.invalidLength(0)) {
            try empty.copyDataBytes(
                to: UnsafeMutableRawBufferPointer(start: nil, count: 0)
            )
        }
        #expect(throws: CMBlockBufferError.invalidLength(0)) {
            try empty.replaceDataBytes(
                with: UnsafeRawBufferPointer(start: nil, count: 0)
            )
        }
        #expect(throws: CMBlockBufferError.emptyBuffer) {
            try empty.fillDataBytes(with: 0)
        }
        let permitted = try CMBlockBuffer(
            bufferReference: empty,
            flags: .permitEmptyReference
        )
        #expect(permitted.isEmpty)

        #expect(throws: CMBlockBufferError.invalidCapacity(-1)) {
            _ = try CMBlockBuffer(capacity: -1)
        }

        let segmented = try makeBuffer(length: 2)
        let pointer = UnsafeMutableRawPointer.allocate(
            byteCount: 2,
            alignment: 2
        )
        pointer.initializeMemory(
            as: UInt8.self,
            repeating: 0,
            count: 2
        )
        try segmented.buffer.append(
            buffer: UnsafeMutableRawBufferPointer(
                start: pointer,
                count: 2
            ),
            deallocator: { releasedPointer, _ in
                releasedPointer.deallocate()
            }
        )
        #expect(throws: CMBlockBufferError.allocationFailed(length: 4)) {
            _ = try segmented.buffer.makeContiguous(
                allocator: { _ in nil },
                deallocator: { _, _ in }
            )
        }
        #expect(throws: CMBlockBufferError.unsupportedFlags(
            rawValue: CMBlockBuffer.Flags.dontOptimizeDepth.rawValue
        )) {
            _ = try segmented.buffer.makeContiguous(
                allocator: { _ in nil },
                deallocator: { _, _ in },
                flags: .dontOptimizeDepth
            )
        }
    }

    @Test("Zero-length views never become silent copy operations")
    func zeroLengthView() throws {
        let fixture = try makeBuffer(length: 4)
        let view = fixture.buffer[2..<2]

        #expect(view.dataLength == 0)
        #expect(view.isContiguous)
        #expect(throws: CMBlockBufferError.emptyBuffer) {
            try view.withContiguousStorage { _ in }
        }
        #expect(throws: CMBlockBufferError.invalidLength(0)) {
            try view.copyDataBytes(
                to: UnsafeMutableRawBufferPointer(start: nil, count: 0)
            )
        }
        #expect(throws: CMBlockBufferError.invalidLength(0)) {
            try view.replaceDataBytes(
                with: UnsafeRawBufferPointer(start: nil, count: 0)
            )
        }
        try view.fillDataBytes(with: 7)
        #expect(throws: CMBlockBufferError.invalidLength(0)) {
            _ = try view.makeContiguous(
                allocator: { _ in nil },
                deallocator: { _, _ in }
            )
        }
        #expect(!fixture.buffer[4..<4].isContiguous)
    }

    @Test("Adjacent shared views coalesce without moving payload bytes")
    func adjacentViewCoalescing() throws {
        let source = try makeBuffer(length: 8)
        let aggregate = try CMBlockBuffer(capacity: 2)

        try aggregate.append(bufferReference: source.buffer[0..<4])
        try aggregate.append(bufferReference: source.buffer[4..<8])

        #expect(aggregate.dataLength == 8)
        #expect(aggregate.isContiguous)
        try aggregate.withContiguousStorage { bytes in
            #expect(bytes.baseAddress == UnsafeRawPointer(source.pointer))
            #expect(bytes.count == 8)
        }
    }

    @Test("References retain leases after the source owner is destroyed")
    func referenceOutlivesSource() throws {
        let releaseCounter = BlockReleaseCounter()
        var reference: CMBlockBuffer?

        do {
            let pointer = UnsafeMutableRawPointer.allocate(
                byteCount: 4,
                alignment: 4
            )
            pointer.initializeMemory(
                as: UInt8.self,
                repeating: 31,
                count: 4
            )
            let source = try CMBlockBuffer(
                buffer: UnsafeMutableRawBufferPointer(
                    start: pointer,
                    count: 4
                ),
                deallocator: { releasedPointer, length in
                    releaseCounter.record(length: length)
                    releasedPointer.deallocate()
                }
            )
            reference = try CMBlockBuffer(
                bufferReference: source[1..<3]
            )
        }

        #expect(releaseCounter.count == 0)
        try reference?.withContiguousStorage { bytes in
            #expect(bytes.count == 2)
            #expect(bytes[0] == 31)
        }
        reference = nil
        #expect(releaseCounter.count == 1)
    }

    @Test("Aliasing is rejected before segmented copy or replacement")
    func aliasingFailure() throws {
        let source = try makeBuffer(length: 8)
        for index in 0..<8 {
            source.pointer.storeBytes(
                of: UInt8(index),
                toByteOffset: index,
                as: UInt8.self
            )
        }
        let reordered = try CMBlockBuffer(capacity: 2)
        try reordered.append(bufferReference: source.buffer[4..<8])
        try reordered.append(bufferReference: source.buffer[0..<4])

        #expect(throws: CMBlockBufferError.overlappingMemory) {
            try reordered.copyDataBytes(
                to: UnsafeMutableRawBufferPointer(
                    start: source.pointer,
                    count: 8
                )
            )
        }
        #expect(throws: CMBlockBufferError.overlappingMemory) {
            try reordered.replaceDataBytes(
                with: UnsafeRawBufferPointer(
                    start: source.pointer,
                    count: 8
                )
            )
        }
        try source.buffer.withContiguousStorage { bytes in
            for index in bytes.indices {
                #expect(bytes[index] == UInt8(index))
            }
        }
    }

    @Test("Length overflow leaves storage and caller ownership unchanged")
    func lengthOverflow() throws {
        let fixture = try makeBuffer(length: 1)
        let pointer = UnsafeMutableRawPointer.allocate(
            byteCount: 1,
            alignment: 1
        )
        let releaseCounter = BlockReleaseCounter()
        defer {
            pointer.deallocate()
        }

        #expect(throws: CMBlockBufferError.lengthOverflow) {
            try fixture.buffer.append(
                buffer: UnsafeMutableRawBufferPointer(
                    start: pointer,
                    count: Int.max
                ),
                deallocator: { _, length in
                    releaseCounter.record(length: length)
                }
            )
        }
        #expect(fixture.buffer.dataLength == 1)
        #expect(releaseCounter.count == 0)
    }

    @Test("Malformed external views fail before constructing a range")
    func malformedView() throws {
        let fixture = try makeBuffer(length: 4)
        let malformed = MalformedBlockBufferView(
            owner: fixture.buffer,
            startIndex: 3,
            endIndex: 2
        )
        let destination = UnsafeMutableRawPointer.allocate(
            byteCount: 1,
            alignment: 1
        )
        defer {
            destination.deallocate()
        }

        let expected = CMBlockBufferError.invalidRange(
            lowerBound: 3,
            upperBound: 2,
            validLowerBound: 0,
            validUpperBound: 4
        )
        #expect(throws: expected) {
            try fixture.buffer.append(bufferReference: malformed)
        }
        #expect(throws: expected) {
            try malformed.copyDataBytes(
                to: UnsafeMutableRawBufferPointer(
                    start: destination,
                    count: 1
                )
            )
        }
        #expect(fixture.buffer.dataLength == 4)
    }

    private func makeBuffer(
        length: Int
    ) throws -> (
        buffer: CMBlockBuffer,
        releaseCounter: BlockReleaseCounter,
        pointer: UnsafeMutableRawPointer
    ) {
        let pointer = UnsafeMutableRawPointer.allocate(
            byteCount: length,
            alignment: 8
        )
        pointer.initializeMemory(
            as: UInt8.self,
            repeating: 0,
            count: length
        )
        let releaseCounter = BlockReleaseCounter()
        let buffer = try CMBlockBuffer(
            buffer: UnsafeMutableRawBufferPointer(
                start: pointer,
                count: length
            ),
            deallocator: { releasedPointer, releasedLength in
                releaseCounter.record(length: releasedLength)
                releasedPointer.deallocate()
            }
        )
        return (buffer, releaseCounter, pointer)
    }
}

private enum CMBlockBufferBorrowTestError: Error {
    case expected
}

private struct MalformedBlockBufferView: CMBlockBufferProtocol {
    let owner: CMBlockBuffer
    let startIndex: Int
    let endIndex: Int
}

private final class BlockReleaseCounter {
    private(set) var count = 0
    private(set) var releasedLength = 0

    func record(length: Int) {
        count += 1
        releasedLength = length
    }
}

private final class BlockAllocationCounter {
    private(set) var allocationCount = 0
    private(set) var releaseCount = 0

    func allocate(length: Int) -> UnsafeMutableRawPointer {
        allocationCount += 1
        return UnsafeMutableRawPointer.allocate(
            byteCount: length,
            alignment: 8
        )
    }

    func release(
        pointer: UnsafeMutableRawPointer,
        length: Int
    ) {
        releaseCount += 1
        pointer.deallocate()
    }
}
