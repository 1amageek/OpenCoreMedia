import OpenCoreMedia

enum OpenCoreMediaPortableCompletionSmoke {
    static func verify() throws {
        let attachmentBytes = CMAttachmentBytes([1, 2, 3])
        guard attachmentBytes.count == 3 else {
            throw OpenCoreMediaPortableCompletionSmokeError.contractViolated
        }

        let simpleQueue = try CMSimpleQueue<Int>(capacity: 2)
        try simpleQueue.enqueue(1)
        guard simpleQueue.dequeue() == 1 else {
            throw OpenCoreMediaPortableCompletionSmokeError.contractViolated
        }

        let bufferQueue = try CMBufferQueue<Int>(
            capacity: 1,
            callbacks: CMBufferQueueCallbacks(duration: { _ in .zero })
        )
        try bufferQueue.enqueue(1)
        guard bufferQueue.count == 1, bufferQueue.duration == .zero else {
            throw OpenCoreMediaPortableCompletionSmokeError.contractViolated
        }

        let clock = CMClock(
            source: OpenCoreMediaPortableConstantClockSource()
        )
        let timebase = try CMTimebase(sourceClock: clock)
        try timebase.setRateAndAnchorTime(
            rate: 1,
            anchorTime: .zero,
            referenceTime: .zero
        )
        guard try timebase.time() == CMTime(value: 5, timescale: 1) else {
            throw OpenCoreMediaPortableCompletionSmokeError.contractViolated
        }

        let pointer = UnsafeMutableRawPointer.allocate(
            byteCount: 2,
            alignment: 2
        )
        let block = try CMBlockBuffer(
            buffer: UnsafeMutableRawBufferPointer(
                start: pointer,
                count: 2
            ),
            deallocator: { pointer, _ in pointer.deallocate() }
        )
        let dimensions = try CVPixelDimensions(width: 1, height: 1)
        let format = CMImmutableVideoFormatDescription(
            dimensions: dimensions,
            pixelFormat: .bgra32
        )
        let sample = try CMBlockSampleBuffer(
            dataBuffer: block,
            formatDescription: format,
            sampleCount: 2,
            timing: [],
            sampleSizes: [1]
        )
        guard try sample.sampleSize(at: 1) == 1,
              try sample.sampleData(at: 1).dataLength == 1
        else {
            throw OpenCoreMediaPortableCompletionSmokeError.contractViolated
        }
        let sampleData = try sample.sampleData(at: 1)
        requireSendable(block)
        requireSendable(sample)
        requireSendable(sampleData)
    }

    private static func requireSendable<Value: Sendable>(
        _ value: borrowing Value
    ) {}
}

private struct OpenCoreMediaPortableConstantClockSource: CMClockSource {
    let mightDrift = false

    func currentTime() throws(CMClockError) -> CMTime {
        CMTime(value: 5, timescale: 1)
    }
}

private enum OpenCoreMediaPortableCompletionSmokeError: Error {
    case contractViolated
}
