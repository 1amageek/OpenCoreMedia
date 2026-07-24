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
            upperBound: 8,
            validLowerBound: 0,
            validUpperBound: 8
        )) {
            try fixture.buffer.withUnsafeMutableBytes(
                atOffset: 9
            ) { _ in }
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

        slice.fillDataBytes(with: 7)
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
    }

    private func makeBuffer(
        length: Int
    ) throws -> (
        buffer: CMBlockBuffer,
        releaseCounter: BlockReleaseCounter
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
        return (buffer, releaseCounter)
    }
}

private final class BlockReleaseCounter {
    private(set) var count = 0
    private(set) var releasedLength = 0

    func record(length: Int) {
        count += 1
        releasedLength = length
    }
}
