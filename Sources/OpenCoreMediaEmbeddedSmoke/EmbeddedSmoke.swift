import OpenCoreMedia

@main
struct OpenCoreMediaEmbeddedSmoke {
    static func main() throws {
        let dimensions = try CVPixelDimensions(width: 2, height: 1)
        let image = try CVPackedPixelBuffer(
            dimensions: dimensions,
            pixelFormat: .bgra32,
            bytesPerPixel: 4,
            bytesPerRow: 8
        )
        let format = CMImmutableVideoFormatDescription(
            dimensions: dimensions,
            pixelFormat: .bgra32
        )
        let timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: CMTime(
                value: 10,
                timescale: 30
            ),
            decodeTimeStamp: .invalid
        )
        let sample = try CMImageSampleBuffer(
            imageBuffer: image,
            formatDescription: format,
            timing: [timing]
        )

        guard sample.sampleAttachments(
            createIfNecessary: false
        ) == nil else {
            throw OpenCoreMediaEmbeddedSmokeError.unexpectedMaterialization
        }

        let source = sample.sampleAttachments[0]
        source.setBoolean(true, for: .notSync)
        source[rawAttachment: "smoke.metadata"] = .array([
            .integer(1),
            .dictionary(["ready": .boolean(true)])
        ])
        let propagatedKey = CMAttachmentKey(
            rawValue: "smoke.propagated"
        )
        sample.attachments[propagatedKey] = .shouldPropagate(
            .integer(7)
        )

        try sample.setDataReadiness(.notReady)
        do {
            _ = try sample.imageBuffer()
            throw OpenCoreMediaEmbeddedSmokeError.readinessIgnored
        } catch CMSampleBufferError.dataNotReady {
        }
        try sample.setDataReadiness(.failed(code: 17))
        do {
            _ = try sample.imageBuffer()
            throw OpenCoreMediaEmbeddedSmokeError.readinessFailureIgnored
        } catch CMSampleBufferError.dataFailed(code: 17) {
        }
        try sample.setDataReadiness(.ready)

        let pointer = UnsafeMutableRawPointer.allocate(
            byteCount: 8,
            alignment: 8
        )
        pointer.initializeMemory(
            as: UInt8.self,
            repeating: 1,
            count: 8
        )
        let block = try CMBlockBuffer(
            buffer: UnsafeMutableRawBufferPointer(
                start: pointer,
                count: 8
            ),
            deallocator: { releasedPointer, _ in
                releasedPointer.deallocate()
            }
        )
        do {
            try block.withContiguousStorage { _ -> Void in
                throw OpenCoreMediaEmbeddedBorrowError.expected
            }
            throw OpenCoreMediaEmbeddedSmokeError.borrowFailureIgnored
        } catch OpenCoreMediaEmbeddedBorrowError.expected {
        }

        let appendedPointer = UnsafeMutableRawPointer.allocate(
            byteCount: 4,
            alignment: 4
        )
        appendedPointer.initializeMemory(
            as: UInt8.self,
            repeating: 2,
            count: 4
        )
        try block.append(
            buffer: UnsafeMutableRawBufferPointer(
                start: appendedPointer,
                count: 4
            ),
            deallocator: { releasedPointer, _ in
                releasedPointer.deallocate()
            }
        )
        guard block.dataLength == 12, !block.isContiguous else {
            throw OpenCoreMediaEmbeddedSmokeError.segmentContractViolated
        }
        do {
            try block.withContiguousStorage { _ in }
            throw OpenCoreMediaEmbeddedSmokeError.segmentContractViolated
        } catch CMBlockBufferError.nonContiguousStorage {
        }
        try block[6..<10].fillDataBytes(with: 3)

        let copiedPointer = UnsafeMutableRawPointer.allocate(
            byteCount: 12,
            alignment: 4
        )
        defer {
            copiedPointer.deallocate()
        }
        try block.copyDataBytes(
            to: UnsafeMutableRawBufferPointer(
                start: copiedPointer,
                count: 12
            )
        )
        guard copiedPointer.load(as: UInt8.self) == 1,
              copiedPointer.load(
                  fromByteOffset: 6,
                  as: UInt8.self
              ) == 3,
              copiedPointer.load(
                  fromByteOffset: 9,
                  as: UInt8.self
              ) == 3,
              copiedPointer.load(
                  fromByteOffset: 10,
                  as: UInt8.self
              ) == 2
        else {
            throw OpenCoreMediaEmbeddedSmokeError.segmentContractViolated
        }

        let replacementPointer = UnsafeMutableRawPointer.allocate(
            byteCount: 4,
            alignment: 4
        )
        defer {
            replacementPointer.deallocate()
        }
        replacementPointer.initializeMemory(
            as: UInt8.self,
            repeating: 5,
            count: 4
        )
        try block[6..<10].replaceDataBytes(
            with: UnsafeRawBufferPointer(
                start: replacementPointer,
                count: 4
            )
        )
        try block.copyDataBytes(
            to: UnsafeMutableRawBufferPointer(
                start: copiedPointer,
                count: 12
            )
        )
        guard copiedPointer.load(
            fromByteOffset: 6,
            as: UInt8.self
        ) == 5,
            copiedPointer.load(
                fromByteOffset: 9,
                as: UInt8.self
            ) == 5
        else {
            throw OpenCoreMediaEmbeddedSmokeError.segmentContractViolated
        }

        let reference = try CMBlockBuffer(
            bufferReference: block[4..<8],
            flags: [.assureMemoryNow, .dontOptimizeDepth]
        )
        guard reference.dataLength == 4, reference.isContiguous else {
            throw OpenCoreMediaEmbeddedSmokeError.segmentContractViolated
        }
        let forcedCopy = try reference.makeContiguous(
            allocator: { length in
                UnsafeMutableRawPointer.allocate(
                    byteCount: length,
                    alignment: 4
                )
            },
            deallocator: { releasedPointer, _ in
                releasedPointer.deallocate()
            },
            flags: .alwaysCopyData
        )
        try forcedCopy.withContiguousStorage { bytes in
            guard bytes.baseAddress
                != UnsafeRawPointer(pointer.advanced(by: 4))
            else {
                throw OpenCoreMediaEmbeddedSmokeError.segmentContractViolated
            }
        }

        do {
            _ = try block.makeContiguous(
                allocator: { _ in nil },
                deallocator: { _, _ in }
            )
            throw OpenCoreMediaEmbeddedSmokeError.segmentContractViolated
        } catch CMBlockBufferError.allocationFailed(length: 12) {
        }

        let contiguousBlock = try block.makeContiguous(
            allocator: { length in
                UnsafeMutableRawPointer.allocate(
                    byteCount: length,
                    alignment: 4
                )
            },
            deallocator: { releasedPointer, _ in
                releasedPointer.deallocate()
            }
        )
        guard contiguousBlock.isContiguous,
              contiguousBlock.dataLength == block.dataLength
        else {
            throw OpenCoreMediaEmbeddedSmokeError.segmentContractViolated
        }

        let copy = try sample.copy(withTiming: [timing])
        let copied = copy.sampleAttachments[0]
        guard try copied.booleanValue(for: .notSync) == true,
              copied[rawAttachment: "smoke.metadata"] == .array([
                  .integer(1),
                  .dictionary(["ready": .boolean(true)])
              ]),
              copy.attachments[propagatedKey] == .shouldPropagate(
                  .integer(7)
              ),
              try sample.imageBuffer() === copy.imageBuffer()
        else {
            throw OpenCoreMediaEmbeddedSmokeError.copyContractViolated
        }

        source.setBoolean(false, for: .notSync)
        guard try copied.booleanValue(for: .notSync) == true else {
            throw OpenCoreMediaEmbeddedSmokeError.metadataAliased
        }

        try verifyBlockAliasingFailure()
        try verifyBlockLeaseRelease()
    }

    private static func verifyBlockAliasingFailure() throws {
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
            throw OpenCoreMediaEmbeddedSmokeError.aliasAccepted
        } catch CMBlockBufferError.overlappingMemory {
        }
        do {
            try reordered.replaceDataBytes(
                with: UnsafeRawBufferPointer(
                    start: pointer,
                    count: 8
                )
            )
            throw OpenCoreMediaEmbeddedSmokeError.aliasAccepted
        } catch CMBlockBufferError.overlappingMemory {
        }
        try source.withContiguousStorage { bytes in
            for index in bytes.indices {
                guard bytes[index] == UInt8(index) else {
                    throw OpenCoreMediaEmbeddedSmokeError.aliasAccepted
                }
            }
        }
    }

    private static func verifyBlockLeaseRelease() throws {
        let counter = OpenCoreMediaEmbeddedReleaseCounter()
        var reference: CMBlockBuffer?

        do {
            let firstPointer = UnsafeMutableRawPointer.allocate(
                byteCount: 2,
                alignment: 2
            )
            let buffer = try CMBlockBuffer(
                buffer: UnsafeMutableRawBufferPointer(
                    start: firstPointer,
                    count: 2
                ),
                deallocator: { pointer, _ in
                    counter.record()
                    pointer.deallocate()
                }
            )
            let secondPointer = UnsafeMutableRawPointer.allocate(
                byteCount: 2,
                alignment: 2
            )
            try buffer.append(
                buffer: UnsafeMutableRawBufferPointer(
                    start: secondPointer,
                    count: 2
                ),
                deallocator: { pointer, _ in
                    counter.record()
                    pointer.deallocate()
                }
            )
            reference = CMBlockBuffer(referencing: buffer)
        }

        guard counter.count == 0, reference?.dataLength == 4 else {
            throw OpenCoreMediaEmbeddedSmokeError.releaseContractViolated
        }
        reference = nil
        guard counter.count == 2 else {
            throw OpenCoreMediaEmbeddedSmokeError.releaseContractViolated
        }
    }
}

enum OpenCoreMediaEmbeddedSmokeError: Error {
    case unexpectedMaterialization
    case readinessIgnored
    case readinessFailureIgnored
    case borrowFailureIgnored
    case segmentContractViolated
    case releaseContractViolated
    case aliasAccepted
    case copyContractViolated
    case metadataAliased
}

enum OpenCoreMediaEmbeddedBorrowError: Error {
    case expected
}

final class OpenCoreMediaEmbeddedReleaseCounter {
    private(set) var count = 0

    func record() {
        count += 1
    }
}
