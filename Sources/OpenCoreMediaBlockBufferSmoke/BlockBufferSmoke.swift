import OpenCoreMedia

@main
struct OpenCoreMediaBlockBufferSmoke {
    static func main() throws {
        try verifySegmentOperations()
        try verifyAliasingFailure()
        try verifyLeaseRelease()
    }

    private static func verifySegmentOperations() throws {
        let firstPointer = UnsafeMutableRawPointer.allocate(
            byteCount: 4,
            alignment: 4
        )
        for index in 0..<4 {
            firstPointer.storeBytes(
                of: UInt8(index),
                toByteOffset: index,
                as: UInt8.self
            )
        }
        let buffer = try CMBlockBuffer(
            buffer: UnsafeMutableRawBufferPointer(
                start: firstPointer,
                count: 4
            ),
            deallocator: { pointer, _ in
                pointer.deallocate()
            }
        )

        let secondPointer = UnsafeMutableRawPointer.allocate(
            byteCount: 4,
            alignment: 4
        )
        for index in 0..<4 {
            secondPointer.storeBytes(
                of: UInt8(index + 4),
                toByteOffset: index,
                as: UInt8.self
            )
        }
        try buffer.append(
            buffer: UnsafeMutableRawBufferPointer(
                start: secondPointer,
                count: 4
            ),
            deallocator: { pointer, _ in
                pointer.deallocate()
            }
        )

        guard buffer.dataLength == 8, !buffer.isContiguous else {
            throw OpenCoreMediaBlockBufferSmokeError.contractViolated
        }
        do {
            try buffer.withContiguousStorage { _ in }
            throw OpenCoreMediaBlockBufferSmokeError.contractViolated
        } catch CMBlockBufferError.nonContiguousStorage {
        }

        try buffer[2..<6].fillDataBytes(with: 9)
        let replacement = UnsafeMutableRawPointer.allocate(
            byteCount: 4,
            alignment: 4
        )
        defer {
            replacement.deallocate()
        }
        replacement.initializeMemory(
            as: UInt8.self,
            repeating: 7,
            count: 4
        )
        try buffer[2..<6].replaceDataBytes(
            with: UnsafeRawBufferPointer(
                start: replacement,
                count: 4
            )
        )

        let copied = UnsafeMutableRawPointer.allocate(
            byteCount: 8,
            alignment: 4
        )
        defer {
            copied.deallocate()
        }
        try buffer.copyDataBytes(
            to: UnsafeMutableRawBufferPointer(
                start: copied,
                count: 8
            )
        )
        guard copied.load(as: UInt8.self) == 0,
              copied.load(fromByteOffset: 2, as: UInt8.self) == 7,
              copied.load(fromByteOffset: 5, as: UInt8.self) == 7,
              copied.load(fromByteOffset: 7, as: UInt8.self) == 7
        else {
            throw OpenCoreMediaBlockBufferSmokeError.contractViolated
        }

        let reference = try CMBlockBuffer(
            bufferReference: buffer[1..<3],
            flags: [.assureMemoryNow, .dontOptimizeDepth]
        )
        guard reference.isContiguous, reference.dataLength == 2 else {
            throw OpenCoreMediaBlockBufferSmokeError.contractViolated
        }

        let contiguous = try buffer.makeContiguous(
            allocator: { length in
                UnsafeMutableRawPointer.allocate(
                    byteCount: length,
                    alignment: 4
                )
            },
            deallocator: { pointer, _ in
                pointer.deallocate()
            }
        )
        guard contiguous.isContiguous, contiguous.dataLength == 8 else {
            throw OpenCoreMediaBlockBufferSmokeError.contractViolated
        }
        do {
            _ = try buffer.makeContiguous(
                allocator: { _ in nil },
                deallocator: { _, _ in }
            )
            throw OpenCoreMediaBlockBufferSmokeError.contractViolated
        } catch CMBlockBufferError.allocationFailed(length: 8) {
        }
    }

    private static func verifyAliasingFailure() throws {
        let pointer = UnsafeMutableRawPointer.allocate(
            byteCount: 8,
            alignment: 8
        )
        for index in 0..<8 {
            pointer.storeBytes(
                of: UInt8(index),
                toByteOffset: index,
                as: UInt8.self
            )
        }
        let source = try CMBlockBuffer(
            buffer: UnsafeMutableRawBufferPointer(
                start: pointer,
                count: 8
            ),
            deallocator: { releasedPointer, _ in
                releasedPointer.deallocate()
            }
        )
        let reordered = try CMBlockBuffer(capacity: 2)
        try reordered.append(bufferReference: source[4..<8])
        try reordered.append(bufferReference: source[0..<4])

        do {
            try reordered.copyDataBytes(
                to: UnsafeMutableRawBufferPointer(
                    start: pointer,
                    count: 8
                )
            )
            throw OpenCoreMediaBlockBufferSmokeError.aliasAccepted
        } catch CMBlockBufferError.overlappingMemory {
        }
        do {
            try reordered.replaceDataBytes(
                with: UnsafeRawBufferPointer(
                    start: pointer,
                    count: 8
                )
            )
            throw OpenCoreMediaBlockBufferSmokeError.aliasAccepted
        } catch CMBlockBufferError.overlappingMemory {
        }
    }

    private static func verifyLeaseRelease() throws {
        let counter = OpenCoreMediaBlockBufferReleaseCounter()
        var reference: CMBlockBuffer?

        do {
            let pointer = UnsafeMutableRawPointer.allocate(
                byteCount: 2,
                alignment: 2
            )
            let buffer = try CMBlockBuffer(
                buffer: UnsafeMutableRawBufferPointer(
                    start: pointer,
                    count: 2
                ),
                deallocator: { releasedPointer, _ in
                    counter.record()
                    releasedPointer.deallocate()
                }
            )
            reference = CMBlockBuffer(referencing: buffer)
        }

        guard counter.count == 0, reference?.dataLength == 2 else {
            throw OpenCoreMediaBlockBufferSmokeError.releaseContractViolated
        }
        reference = nil
        guard counter.count == 1 else {
            throw OpenCoreMediaBlockBufferSmokeError.releaseContractViolated
        }
    }
}
