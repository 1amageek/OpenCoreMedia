#if canImport(CoreMedia)
import CoreMedia
import OpenCoreMedia
import Testing

@Suite("CMBlockBuffer Apple differential")
struct CMBlockBufferAppleDifferentialTests {
    @Test("Segmented ranges and explicit copies match Apple behavior")
    func segmentedRanges() throws {
        let applePointers = makePointers()
        defer {
            applePointers.first.deallocate()
            applePointers.second.deallocate()
        }
        let apple = try CoreMedia.CMBlockBuffer(capacity: 2)
        try apple.append(
            buffer: UnsafeMutableRawBufferPointer(
                start: applePointers.first,
                count: 4
            ),
            deallocator: { _, _ in }
        )
        try apple.append(
            buffer: UnsafeMutableRawBufferPointer(
                start: applePointers.second,
                count: 4
            ),
            deallocator: { _, _ in }
        )

        let portablePointers = makePointers()
        defer {
            portablePointers.first.deallocate()
            portablePointers.second.deallocate()
        }
        let portable = try OpenCoreMedia.CMBlockBuffer(capacity: 2)
        try portable.append(
            buffer: UnsafeMutableRawBufferPointer(
                start: portablePointers.first,
                count: 4
            ),
            deallocator: { _, _ in }
        )
        try portable.append(
            buffer: UnsafeMutableRawBufferPointer(
                start: portablePointers.second,
                count: 4
            ),
            deallocator: { _, _ in }
        )

        #expect(portable.dataLength == apple.dataLength)
        #expect(portable.isEmpty == apple.isEmpty)
        #expect(portable.isContiguous == apple.isContiguous)
        #expect(
            portable[0..<4].isContiguous
                == apple[0..<4].isContiguous
        )
        #expect(
            portable[2..<6].isContiguous
                == apple[2..<6].isContiguous
        )
        #expect(operationThrows {
            try portable.withContiguousStorage { _ in }
        })
        #expect(!operationThrows {
            try apple.withContiguousStorage { _ in }
        })

        var appleBorrowCount = 0
        var portableBorrowCount = 0
        try apple.withUnsafeMutableBytes(atOffset: 2) { bytes in
            appleBorrowCount = bytes.count
        }
        try portable.withUnsafeMutableBytes(atOffset: 2) { bytes in
            portableBorrowCount = bytes.count
        }
        #expect(portableBorrowCount == appleBorrowCount)
        #expect(operationThrows {
            try portable.withUnsafeMutableBytes(atOffset: 8) { _ in }
        } == operationThrows {
            try apple.withUnsafeMutableBytes(atOffset: 8) { _ in }
        })

        let appleCopy = UnsafeMutableRawPointer.allocate(
            byteCount: 8,
            alignment: 8
        )
        let portableCopy = UnsafeMutableRawPointer.allocate(
            byteCount: 8,
            alignment: 8
        )
        defer {
            appleCopy.deallocate()
            portableCopy.deallocate()
        }
        try apple.copyDataBytes(
            to: UnsafeMutableRawBufferPointer(
                start: appleCopy,
                count: 8
            )
        )
        try portable.copyDataBytes(
            to: UnsafeMutableRawBufferPointer(
                start: portableCopy,
                count: 8
            )
        )
        for index in 0..<8 {
            #expect(
                portableCopy.load(
                    fromByteOffset: index,
                    as: UInt8.self
                ) == appleCopy.load(
                    fromByteOffset: index,
                    as: UInt8.self
                )
            )
        }
    }

    @Test("Empty references and contiguous materialization are explicit")
    func emptyAndMaterialized() throws {
        let appleEmpty = try CoreMedia.CMBlockBuffer(capacity: 1)
        let portableEmpty = try OpenCoreMedia.CMBlockBuffer(capacity: 1)

        #expect(portableEmpty.isEmpty == appleEmpty.isEmpty)
        #expect(portableEmpty.dataLength == appleEmpty.dataLength)
        #expect(portableEmpty.isContiguous == appleEmpty.isContiguous)
        #expect(operationThrows {
            _ = try OpenCoreMedia.CMBlockBuffer(
                bufferReference: portableEmpty
            )
        } == operationThrows {
            _ = try CoreMedia.CMBlockBuffer(
                bufferReference: appleEmpty
            )
        })

        let portablePermitted = try OpenCoreMedia.CMBlockBuffer(
            bufferReference: portableEmpty,
            flags: .permitEmptyReference
        )
        #expect(portablePermitted.isEmpty)
        // The macOS 27 beta overlay currently returns
        // kCMBlockBufferBadLengthParameterErr here despite its documentation
        // stating that permitEmptyReference accepts this operation.
        #expect(operationThrows {
            _ = try CoreMedia.CMBlockBuffer(
                bufferReference: appleEmpty,
                flags: .permitEmptyReference
            )
        })
        #expect(operationThrows {
            try portableEmpty.copyDataBytes(
                to: UnsafeMutableRawBufferPointer(start: nil, count: 0)
            )
        } == operationThrows {
            try appleEmpty.copyDataBytes(
                to: UnsafeMutableRawBufferPointer(start: nil, count: 0)
            )
        })
        #expect(operationThrows {
            try portableEmpty.replaceDataBytes(
                with: UnsafeRawBufferPointer(start: nil, count: 0)
            )
        } == operationThrows {
            try appleEmpty.replaceDataBytes(
                with: UnsafeRawBufferPointer(start: nil, count: 0)
            )
        })
        #expect(operationThrows {
            try portableEmpty.fillDataBytes(with: 0)
        } == operationThrows {
            try appleEmpty.fillDataBytes(with: 0)
        })

        let applePointers = makePointers()
        let portablePointers = makePointers()
        defer {
            applePointers.first.deallocate()
            applePointers.second.deallocate()
            portablePointers.first.deallocate()
            portablePointers.second.deallocate()
        }
        let apple = try CoreMedia.CMBlockBuffer(capacity: 2)
        let portable = try OpenCoreMedia.CMBlockBuffer(capacity: 2)
        try append(
            first: applePointers.first,
            second: applePointers.second,
            to: apple
        )
        try append(
            first: portablePointers.first,
            second: portablePointers.second,
            to: portable
        )

        let appleContiguous = try apple.makeContiguous(
            allocator: { length in
                UnsafeMutableRawPointer.allocate(
                    byteCount: length,
                    alignment: 8
                )
            },
            deallocator: { pointer, _ in
                pointer.deallocate()
            }
        )
        let portableContiguous = try portable.makeContiguous(
            allocator: { length in
                UnsafeMutableRawPointer.allocate(
                    byteCount: length,
                    alignment: 8
                )
            },
            deallocator: { pointer, _ in
                pointer.deallocate()
            }
        )
        #expect(
            portableContiguous.isContiguous
                == appleContiguous.isContiguous
        )
        #expect(
            portableContiguous.dataLength
                == appleContiguous.dataLength
        )

        let appleCopy = UnsafeMutableRawPointer.allocate(
            byteCount: 8,
            alignment: 8
        )
        let portableCopy = UnsafeMutableRawPointer.allocate(
            byteCount: 8,
            alignment: 8
        )
        defer {
            appleCopy.deallocate()
            portableCopy.deallocate()
        }
        try appleContiguous.copyDataBytes(
            to: UnsafeMutableRawBufferPointer(
                start: appleCopy,
                count: 8
            )
        )
        try portableContiguous.copyDataBytes(
            to: UnsafeMutableRawBufferPointer(
                start: portableCopy,
                count: 8
            )
        )
        for index in 0..<8 {
            #expect(
                portableCopy.load(
                    fromByteOffset: index,
                    as: UInt8.self
                ) == appleCopy.load(
                    fromByteOffset: index,
                    as: UInt8.self
                )
            )
        }
    }

    @Test("Reference flags match Apple while empty slice semantics stay typed")
    func referenceFlagsAndEmptySlice() throws {
        let applePointers = makePointers()
        let portablePointers = makePointers()
        defer {
            applePointers.first.deallocate()
            applePointers.second.deallocate()
            portablePointers.first.deallocate()
            portablePointers.second.deallocate()
        }
        let appleSource = try CoreMedia.CMBlockBuffer(
            buffer: UnsafeMutableRawBufferPointer(
                start: applePointers.first,
                count: 4
            ),
            deallocator: { _, _ in }
        )
        let portableSource = try OpenCoreMedia.CMBlockBuffer(
            buffer: UnsafeMutableRawBufferPointer(
                start: portablePointers.first,
                count: 4
            ),
            deallocator: { _, _ in }
        )
        let flags: CoreMedia.CMBlockBuffer.Flags =
            [.assureMemoryNow, .dontOptimizeDepth]
        let appleReference = try CoreMedia.CMBlockBuffer(
            bufferReference: appleSource,
            flags: flags
        )
        let portableReference = try OpenCoreMedia.CMBlockBuffer(
            bufferReference: portableSource,
            flags: [.assureMemoryNow, .dontOptimizeDepth]
        )
        #expect(portableReference.dataLength == appleReference.dataLength)

        let appleAggregate = try CoreMedia.CMBlockBuffer(capacity: 1)
        let portableAggregate = try OpenCoreMedia.CMBlockBuffer(capacity: 1)
        try appleAggregate.append(
            bufferReference: appleSource,
            flags: .dontOptimizeDepth
        )
        try portableAggregate.append(
            bufferReference: portableSource,
            flags: .dontOptimizeDepth
        )
        #expect(portableAggregate.dataLength == appleAggregate.dataLength)

        let appleEmptySlice = appleSource[2..<2]
        let portableEmptySlice = portableSource[2..<2]
        #expect(portableEmptySlice.dataLength == 0)
        #expect(appleEmptySlice.dataLength == 0)
        #expect(
            portableEmptySlice.isContiguous
                == appleEmptySlice.isContiguous
        )
        #expect(operationThrows {
            try portableEmptySlice.copyDataBytes(
                to: UnsafeMutableRawBufferPointer(start: nil, count: 0)
            )
        } == operationThrows {
            try appleEmptySlice.copyDataBytes(
                to: UnsafeMutableRawBufferPointer(start: nil, count: 0)
            )
        })
        // The macOS 27 beta overlay interprets a zero-length slice as
        // "remaining bytes" only for makeContiguous. OpenCoreMedia preserves
        // the slice's zero dataLength and rejects that materialization.
        #expect(operationThrows {
            _ = try portableEmptySlice.makeContiguous(
                allocator: { _ in nil },
                deallocator: { _, _ in }
            )
        })
        #expect(!operationThrows {
            _ = try appleEmptySlice.makeContiguous(
                allocator: { length in
                    UnsafeMutableRawPointer.allocate(
                        byteCount: length,
                        alignment: 1
                    )
                },
                deallocator: { pointer, _ in
                    pointer.deallocate()
                }
            )
        })

        try portableEmptySlice.fillDataBytes(with: 7)
        try appleEmptySlice.fillDataBytes(with: 7)
        #expect(
            portablePointers.first.load(
                fromByteOffset: 2,
                as: UInt8.self
            ) == 2
        )
        #expect(
            applePointers.first.load(
                fromByteOffset: 2,
                as: UInt8.self
            ) == 7
        )

        try appleSource.append(
            buffer: UnsafeMutableRawBufferPointer(
                start: applePointers.second,
                count: 4
            ),
            deallocator: { _, _ in }
        )
        try portableSource.append(
            buffer: UnsafeMutableRawBufferPointer(
                start: portablePointers.second,
                count: 4
            ),
            deallocator: { _, _ in }
        )
        #expect(portableSource[2..<2].isContiguous)
        #expect(!appleSource[2..<2].isContiguous)
    }

    private func makePointers() -> (
        first: UnsafeMutableRawPointer,
        second: UnsafeMutableRawPointer
    ) {
        let first = UnsafeMutableRawPointer.allocate(
            byteCount: 4,
            alignment: 8
        )
        let second = UnsafeMutableRawPointer.allocate(
            byteCount: 4,
            alignment: 8
        )
        for index in 0..<4 {
            first.storeBytes(
                of: UInt8(index),
                toByteOffset: index,
                as: UInt8.self
            )
            second.storeBytes(
                of: UInt8(index + 4),
                toByteOffset: index,
                as: UInt8.self
            )
        }
        return (first, second)
    }

    private func append(
        first: UnsafeMutableRawPointer,
        second: UnsafeMutableRawPointer,
        to buffer: CoreMedia.CMBlockBuffer
    ) throws {
        try buffer.append(
            buffer: UnsafeMutableRawBufferPointer(
                start: first,
                count: 4
            ),
            deallocator: { _, _ in }
        )
        try buffer.append(
            buffer: UnsafeMutableRawBufferPointer(
                start: second,
                count: 4
            ),
            deallocator: { _, _ in }
        )
    }

    private func append(
        first: UnsafeMutableRawPointer,
        second: UnsafeMutableRawPointer,
        to buffer: OpenCoreMedia.CMBlockBuffer
    ) throws {
        try buffer.append(
            buffer: UnsafeMutableRawBufferPointer(
                start: first,
                count: 4
            ),
            deallocator: { _, _ in }
        )
        try buffer.append(
            buffer: UnsafeMutableRawBufferPointer(
                start: second,
                count: 4
            ),
            deallocator: { _, _ in }
        )
    }

    private func operationThrows(
        _ operation: () throws -> Void
    ) -> Bool {
        do {
            try operation()
            return false
        } catch {
            return true
        }
    }
}
#endif
