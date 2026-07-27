import OpenCoreMedia
import OpenCoreMediaFoundation
import Synchronization
import Testing

@Suite("Remaining Core Media surface smoke")
struct CMRemainingSurfaceSmokeTests {
    @Test("Deferred allocation is lazy and releases exactly once")
    func deferredAllocation() throws {
        let allocationCount = Mutex(0)
        let releaseCount = Mutex(0)
        var buffer: CMBlockBuffer? = try CMBlockBuffer(
            blockLength: 16,
            offsetToData: 4,
            dataLength: 8,
            allocator: { length in
                allocationCount.withLock { $0 += 1 }
                let pointer = UnsafeMutableRawPointer.allocate(
                    byteCount: length,
                    alignment: 8
                )
                pointer.initializeMemory(
                    as: UInt8.self,
                    repeating: 7,
                    count: length
                )
                return pointer
            },
            deallocator: { pointer, length in
                releaseCount.withLock { $0 += 1 }
                #expect(length == 16)
                pointer.deallocate()
            }
        )

        #expect(allocationCount.withLock { $0 } == 0)
        #expect(buffer?.dataLength == 8)
        try buffer?.assureBlockMemory()
        try buffer?.assureBlockMemory()
        #expect(allocationCount.withLock { $0 } == 1)
        try buffer?.withContiguousStorage { bytes in
            #expect(bytes.count == 8)
            #expect(bytes[0] == 7)
        }
        buffer = nil
        #expect(releaseCount.withLock { $0 } == 1)

        var appended: CMBlockBuffer? = try CMBlockBuffer(capacity: 1)
        try appended?.append(
            blockLength: 4,
            allocator: { length in
                allocationCount.withLock { $0 += 1 }
                return UnsafeMutableRawPointer.allocate(
                    byteCount: length,
                    alignment: 4
                )
            },
            deallocator: { pointer, _ in
                releaseCount.withLock { $0 += 1 }
                pointer.deallocate()
            }
        )
        #expect(allocationCount.withLock { $0 } == 1)
        try appended?.fillDataBytes(with: 3)
        #expect(allocationCount.withLock { $0 } == 2)
        appended = nil
        #expect(releaseCount.withLock { $0 } == 2)
    }

    @Test("Deferred allocator and byte borrows execute outside state locks")
    func deferredAllocatorAndBorrowReentrancy() throws {
        let holder = Mutex<CMBlockBuffer?>(nil)
        let allocationFailure = Mutex<CMBlockBufferError?>(nil)
        let buffer = try CMBlockBuffer(
            blockLength: 8,
            allocator: { length in
                if let reentrantBuffer = holder.withLock({ $0 }) {
                    do {
                        try reentrantBuffer.assureBlockMemory()
                    } catch let error as CMBlockBufferError {
                        allocationFailure.withLock { $0 = error }
                    } catch {
                        Issue.record("Unexpected deferred allocation error")
                    }
                }
                return UnsafeMutableRawPointer.allocate(
                    byteCount: length,
                    alignment: 8
                )
            },
            deallocator: { pointer, _ in
                pointer.deallocate()
            }
        )
        holder.withLock { $0 = buffer }

        try buffer.assureBlockMemory()
        #expect(
            allocationFailure.withLock { $0 } == .allocationInProgress
        )

        _ = try buffer.withUnsafeMutableBytes { _ in
            #expect(throws: CMBlockBufferError.concurrentAccessConflict) {
                try buffer.withContiguousStorage { _ in
                    Issue.record("Nested read must not enter an active write")
                }
            }
        }
        holder.withLock { $0 = nil }
    }

    @Test("Assured deferred allocation reports failure")
    func assuredAllocationFailure() {
        #expect(throws: CMBlockBufferError.allocationFailed(length: 32)) {
            _ = try CMBlockBuffer(
                blockLength: 32,
                allocator: { _ in nil },
                deallocator: { _, _ in },
                flags: [.assureMemoryNow]
            )
        }
    }

    @Test("Assure flags preflight references and fill is atomic")
    func assureFlagsAndAtomicFill() throws {
        let allocationCount = Mutex(0)
        let source = try CMBlockBuffer(
            blockLength: 4,
            allocator: { length in
                allocationCount.withLock { $0 += 1 }
                return UnsafeMutableRawPointer.allocate(
                    byteCount: length,
                    alignment: 4
                )
            },
            deallocator: { pointer, _ in pointer.deallocate() }
        )
        let reference = try CMBlockBuffer(
            bufferReference: source,
            flags: [.assureMemoryNow]
        )
        #expect(allocationCount.withLock { $0 } == 1)
        _ = try reference.makeContiguous(
            allocator: { _ in nil },
            deallocator: { _, _ in },
            flags: [.assureMemoryNow]
        )
        #expect(allocationCount.withLock { $0 } == 1)

        let firstPointer = UnsafeMutableRawPointer.allocate(
            byteCount: 2,
            alignment: 2
        )
        firstPointer.initializeMemory(
            as: UInt8.self,
            repeating: 9,
            count: 2
        )
        let segmented = try CMBlockBuffer(
            buffer: UnsafeMutableRawBufferPointer(
                start: firstPointer,
                count: 2
            ),
            deallocator: { pointer, _ in pointer.deallocate() }
        )
        try segmented.append(
            blockLength: 2,
            allocator: { _ in nil },
            deallocator: { _, _ in }
        )
        #expect(throws: CMBlockBufferError.allocationFailed(length: 2)) {
            try segmented.fillDataBytes(with: 1)
        }
        try segmented.withUnsafeMutableBytes(atOffset: 0) {
            #expect($0[0] == 9)
            #expect($0[1] == 9)
        }

        let reentrantBuffer = try CMBlockBuffer()
        let observedLength = Mutex(-1)
        try reentrantBuffer.append(
            blockLength: 4,
            allocator: { length in
                observedLength.withLock {
                    $0 = reentrantBuffer.dataLength
                }
                return UnsafeMutableRawPointer.allocate(
                    byteCount: length,
                    alignment: 4
                )
            },
            deallocator: { pointer, _ in pointer.deallocate() },
            flags: [.assureMemoryNow]
        )
        #expect(observedLength.withLock { $0 } == 0)
        #expect(reentrantBuffer.dataLength == 4)
    }

    @Test("Raw buffer ranges preserve base ownership")
    func rawBufferRange() throws {
        let releaseCount = Mutex(0)
        let pointer = UnsafeMutableRawPointer.allocate(
            byteCount: 16,
            alignment: 8
        )
        pointer.initializeMemory(
            as: UInt8.self,
            repeating: 0,
            count: 16
        )
        pointer.storeBytes(of: UInt8(42), toByteOffset: 5, as: UInt8.self)
        let pointerAddress = UInt(bitPattern: pointer)

        var buffer: CMBlockBuffer? = try CMBlockBuffer(
            buffer: UnsafeMutableRawBufferPointer(
                start: pointer,
                count: 16
            ),
            offsetToData: 4,
            dataLength: 8,
            deallocator: { released, length in
                #expect(UInt(bitPattern: released) == pointerAddress)
                #expect(length == 16)
                releaseCount.withLock { $0 += 1 }
                released.deallocate()
            }
        )
        try buffer?.withContiguousStorage { bytes in
            #expect(
                bytes.baseAddress
                    == UnsafeRawPointer(pointer.advanced(by: 4))
            )
            #expect(bytes[1] == 42)
        }
        buffer = nil
        #expect(releaseCount.withLock { $0 } == 1)

        let appendedPointer = UnsafeMutableRawPointer.allocate(
            byteCount: 8,
            alignment: 8
        )
        appendedPointer.storeBytes(
            of: UInt8(71),
            toByteOffset: 3,
            as: UInt8.self
        )
        let appendedPointerAddress = UInt(bitPattern: appendedPointer)
        var appended: CMBlockBuffer? = try CMBlockBuffer(capacity: 1)
        try appended?.append(
            buffer: UnsafeMutableRawBufferPointer(
                start: appendedPointer,
                count: 8
            ),
            offsetToData: 2,
            dataLength: 4,
            deallocator: { released, length in
                #expect(
                    UInt(bitPattern: released) == appendedPointerAddress
                )
                #expect(length == 8)
                releaseCount.withLock { $0 += 1 }
                released.deallocate()
            }
        )
        try appended?.withContiguousStorage {
            #expect($0.baseAddress == UnsafeRawPointer(
                appendedPointer.advanced(by: 2)
            ))
            #expect($0[1] == 71)
        }
        appended = nil
        #expect(releaseCount.withLock { $0 } == 2)
    }

    @Test("Retained block-buffer wrappers share mutable observations")
    func retainedBlockBufferStorage() throws {
        let pointer = UnsafeMutableRawPointer.allocate(
            byteCount: 1,
            alignment: 1
        )
        let source = try CMBlockBuffer(
            buffer: UnsafeMutableRawBufferPointer(
                start: pointer,
                count: 1
            ),
            deallocator: { pointer, _ in pointer.deallocate() }
        )
        let retained = CMBlockBuffer(referencing: source)
        let key = CMAttachmentKey(rawValue: "shared")
        retained.attachments[key] = .shouldPropagate(.boolean(true))

        let appendedPointer = UnsafeMutableRawPointer.allocate(
            byteCount: 1,
            alignment: 1
        )
        try source.append(
            buffer: UnsafeMutableRawBufferPointer(
                start: appendedPointer,
                count: 1
            ),
            deallocator: { pointer, _ in pointer.deallocate() }
        )
        #expect(retained.dataLength == 2)
        #expect(source.attachments[key]?.value == .boolean(true))
    }

    @Test("Byte attachments own their bytes and propagate on block buffers")
    func byteAttachments() throws {
        var input: [UInt8] = [1, 2, 3]
        let attachmentBytes = input.withUnsafeBytes {
            CMAttachmentBytes(copying: $0)
        }
        input[0] = 9

        let source = try CMBlockBuffer(capacity: 0)
        let destination = try CMBlockBuffer(capacity: 0)
        CMSetAttachment(
            source,
            key: CMAttachmentKey(rawValue: "bytes"),
            value: .bytes(attachmentBytes),
            attachmentMode: .shouldPropagate
        )
        CMPropagateAttachments(source, destination: destination)

        guard case .bytes(let propagated)? =
            CMGetAttachment(
                destination,
                key: CMAttachmentKey(rawValue: "bytes")
            )?.value
        else {
            Issue.record("Expected an owned byte attachment")
            return
        }
        #expect(propagated.count == 3)
        propagated.withUnsafeBytes {
            #expect($0[0] == 1)
        }

        let adapter = ByteArrayAttachmentAdapter()
        let portable = adapter.portableValue(from: [7, 8])
        #expect(try adapter.platformValue(from: portable) == [7, 8])
    }

    @Test("Multi-sample buffers retain block storage and expose slices")
    func multiSampleBuffer() throws {
        let pointer = UnsafeMutableRawPointer.allocate(
            byteCount: 6,
            alignment: 8
        )
        for index in 0..<6 {
            pointer.storeBytes(
                of: UInt8(index + 1),
                toByteOffset: index,
                as: UInt8.self
            )
        }
        let block = try CMBlockBuffer(
            buffer: UnsafeMutableRawBufferPointer(
                start: pointer,
                count: 6
            ),
            deallocator: { pointer, _ in pointer.deallocate() }
        )
        let dimensions = try CVPixelDimensions(width: 1, height: 1)
        let format = CMImmutableVideoFormatDescription(
            dimensions: dimensions,
            pixelFormat: .bgra32
        )
        let firstTiming = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: .zero,
            decodeTimeStamp: .invalid
        )
        let sample = try CMBlockSampleBuffer(
            dataBuffer: block,
            formatDescription: format,
            sampleCount: 3,
            timing: [firstTiming],
            sampleSizes: [2]
        )

        #expect(try sample.sampleCount() == 3)
        #expect(try sample.dataBuffer() === block)
        #expect(
            try sample.timingInfo(at: 2).presentationTimeStamp
                == CMTime(value: 2, timescale: 30)
        )
        let second = try sample.sampleData(at: 1)
        try second.withContiguousStorage {
            #expect($0.count == 2)
            #expect(
                $0.baseAddress
                    == UnsafeRawPointer(pointer.advanced(by: 2))
            )
            #expect($0[0] == 3)
            #expect($0[1] == 4)
        }

        #expect(throws: CMSampleBufferError.sampleDataLengthMismatch(
            expected: 3,
            actual: 6
        )) {
            _ = try CMBlockSampleBuffer(
                dataBuffer: block,
                formatDescription: format,
                sampleCount: 3,
                timing: [firstTiming],
                sampleSizes: [1]
            )
        }
    }

    @Test("Async readiness performs one explicit transition")
    func asyncReadiness() async throws {
        let invocationCount = Mutex(0)
        let fixture = try makeImageSample(
            readiness: .notReady,
            handler: {
                let invocation = invocationCount.withLock { count in
                    count += 1
                    return count
                }
                return invocation == 1 ? .notReady : .ready
            }
        )
        #expect(throws: CMSampleBufferError.dataNotReady) {
            _ = try fixture.sample.imageBuffer()
        }

        do {
            try await fixture.sample.makeDataReady()
            Issue.record("Expected the first readiness attempt to stay pending")
        } catch CMSampleBufferError.dataNotReady {
        }
        #expect(fixture.sample.dataReadiness == .notReady)
        try await fixture.sample.makeDataReady()
        _ = try fixture.sample.imageBuffer()
        try await fixture.sample.makeDataReady()
        #expect(invocationCount.withLock { $0 } == 2)
    }

    @Test("Readiness is terminal, race-safe, and tracked by copies")
    func readinessTracking() async throws {
        let gate = ReadinessGate()
        let fixture = try makeImageSample(
            readiness: .notReady,
            handler: {
                await gate.suspend()
                return .ready
            }
        )
        let copy = try fixture.sample.copy(
            withTiming: [try fixture.sample.timingInfo(at: 0)]
        )
        let loading = Task {
            try await fixture.sample.makeDataReady()
        }
        while !(await gate.hasStarted()) {
            await Task.yield()
        }
        try copy.setDataReadiness(.failed(code: 31))
        await gate.resume()
        do {
            try await loading.value
            Issue.record("A stale readiness result must not overwrite failure")
        } catch CMSampleBufferError.dataFailed(code: 31) {
        }
        #expect(fixture.sample.dataReadiness == .failed(code: 31))
        #expect(copy.dataReadiness == .failed(code: 31))
        #expect(throws: CMSampleBufferError.invalidReadinessTransition(
            from: .failed(code: 31),
            to: .ready
        )) {
            try fixture.sample.setDataReadiness(.ready)
        }
    }

    @Test("Clock and timebase preserve anchors and rate")
    func clockAndTimebase() async throws {
        let source = TestClockSource(
            time: CMTime(value: 10, timescale: 1)
        )
        let clock = CMClock(source: source)
        let timebase = try CMTimebase(sourceClock: clock)
        try timebase.setRateAndAnchorTime(
            rate: 2,
            anchorTime: CMTime(value: 5, timescale: 1),
            referenceTime: CMTime(value: 10, timescale: 1)
        )
        source.setTime(CMTime(value: 13, timescale: 1))

        #expect(try timebase.time() == CMTime(value: 11, timescale: 1))
        #expect(timebase.effectiveRate == 2)
        #expect(timebase.ultimateSourceClock === clock)
        let anchor = try clock.anchorTime()
        #expect(anchor.clockTime == (try source.currentTime()))
        #expect(anchor.referenceClockTime == source.referenceTime)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<8 {
                group.addTask {
                    try timebase.setRate(Double(index + 1))
                }
                group.addTask {
                    _ = try timebase.time()
                }
            }
            try await group.waitForAll()
        }
        #expect(try timebase.time().isNumeric)

        clock.invalidate()
        #expect(throws: CMClockError.invalidated) {
            _ = try timebase.time()
        }
    }

    @Test("Timebase handles the Int64 boundary without trapping")
    func timebaseIntegerBoundary() throws {
        let source = TestClockSource(time: .zero)
        let clock = CMClock(source: source)
        let timebase = try CMTimebase(sourceClock: clock)
        try timebase.setRateAndAnchorTime(
            rate: 1,
            anchorTime: .zero,
            referenceTime: .zero
        )
        source.setTime(CMTime(value: .max, timescale: 1))
        #expect(
            try timebase.time() == CMTime(value: .max, timescale: 1)
        )
        try timebase.setRateAndAnchorTime(
            rate: 2,
            anchorTime: .zero,
            referenceTime: .zero
        )
        #expect(throws: CMClockError.timeOverflow) {
            _ = try timebase.time()
        }
    }

    @Test("Simple and timed queues enforce capacity and end of data")
    func queues() throws {
        let simple = try CMSimpleQueue<Int>(capacity: 2)
        try simple.enqueue(1)
        try simple.enqueue(2)
        #expect(throws: CMSimpleQueueError.queueIsFull) {
            try simple.enqueue(3)
        }
        #expect(simple.dequeue() == 1)
        #expect(simple.head() == 2)
        try simple.enqueue(3)
        #expect(simple.dequeue() == 2)
        #expect(simple.dequeue() == 3)

        let timed = try CMBufferQueue<TimedQueueValue>(
            capacity: 3,
            callbacks: CMBufferQueueCallbacks(
                duration: { $0.duration },
                presentationTimeStamp: { $0.presentationTimeStamp },
                isDataReady: { $0.isReady },
                compare: {
                    $0.presentationTimeStamp < $1.presentationTimeStamp
                },
                size: { $0.size }
            )
        )
        try timed.enqueue(TimedQueueValue(
            presentationTimeStamp: CMTime(value: 2, timescale: 1),
            duration: CMTime(value: 1, timescale: 1),
            size: 20,
            isReady: true
        ))
        try timed.enqueue(TimedQueueValue(
            presentationTimeStamp: CMTime(value: 1, timescale: 1),
            duration: CMTime(value: 1, timescale: 1),
            size: 10,
            isReady: false
        ))
        #expect(
            timed.firstPresentationTimeStamp()
                == CMTime(value: 1, timescale: 1)
        )
        #expect(timed.dequeueIfDataReady() == nil)
        #expect(timed.duration == CMTime(value: 2, timescale: 1))
        #expect(timed.totalSize == 30)
        timed.markEndOfData()
        #expect(throws: CMBufferQueueError.enqueueAfterEndOfData) {
            try timed.enqueue(TimedQueueValue(
                presentationTimeStamp: .zero,
                duration: CMTime(value: 1, timescale: 1),
                size: 1,
                isReady: true
            ))
        }
        timed.reset()
        #expect(timed.isEmpty)
        #expect(!timed.containsEndOfData)
        try timed.enqueue(TimedQueueValue(
            presentationTimeStamp: .zero,
            duration: .zero,
            size: 1,
            isReady: true
        ))
        #expect(timed.duration == .zero)
    }

    @Test("Queue callbacks and destruction can safely re-enter")
    func queueReentrancy() throws {
        let holder = QueueHolder()
        let queue = try CMBufferQueue<TimedQueueValue>(
            capacity: 4,
            callbacks: CMBufferQueueCallbacks(
                duration: { $0.duration },
                isDataReady: { value in
                    _ = holder.queue?.count
                    return value.isReady
                },
                compare: { left, right in
                    _ = holder.queue?.head()
                    return left.presentationTimeStamp
                        < right.presentationTimeStamp
                }
            )
        )
        holder.queue = queue
        try queue.enqueue(TimedQueueValue(
            presentationTimeStamp: CMTime(value: 2, timescale: 1),
            duration: .zero,
            size: 0,
            isReady: true
        ))
        try queue.enqueue(TimedQueueValue(
            presentationTimeStamp: CMTime(value: 1, timescale: 1),
            duration: .invalid,
            size: 0,
            isReady: true
        ))
        #expect(queue.duration == .invalid)
        _ = queue.dequeueIfDataReady()
        _ = queue.dequeueIfDataReady()
        #expect(queue.duration == .zero)

        let releaseCount = Mutex(0)
        let simpleHolder = SimpleQueueHolder()
        let simple = try CMSimpleQueue<ReentrantRelease>(capacity: 2)
        simpleHolder.queue = simple
        var value: ReentrantRelease? = ReentrantRelease {
            _ = simpleHolder.queue?.count
            releaseCount.withLock { $0 += 1 }
        }
        try simple.enqueue(value!)
        value = nil
        simple.reset()
        #expect(releaseCount.withLock { $0 } == 1)
    }

    @Test("Uniform multi-sample metadata stays compact")
    func compactMultiSampleMetadata() throws {
        let block = try CMBlockBuffer(capacity: 0)
        let dimensions = try CVPixelDimensions(width: 1, height: 1)
        let format = CMImmutableVideoFormatDescription(
            dimensions: dimensions,
            pixelFormat: .bgra32
        )
        let sample = try CMBlockSampleBuffer(
            dataBuffer: block,
            formatDescription: format,
            sampleCount: Int.max,
            timing: [],
            sampleSizes: [0]
        )
        #expect(try sample.sampleCount() == Int.max)
        #expect(try sample.sampleSize(at: Int.max - 1) == 0)
    }

    @Test("Foundation data materialization is an explicit copy")
    func foundationDataBytes() throws {
        let pointer = UnsafeMutableRawPointer.allocate(
            byteCount: 3,
            alignment: 8
        )
        pointer.storeBytes(of: UInt8(4), toByteOffset: 0, as: UInt8.self)
        pointer.storeBytes(of: UInt8(5), toByteOffset: 1, as: UInt8.self)
        pointer.storeBytes(of: UInt8(6), toByteOffset: 2, as: UInt8.self)
        let buffer = try CMBlockBuffer(
            buffer: UnsafeMutableRawBufferPointer(
                start: pointer,
                count: 3
            ),
            deallocator: { pointer, _ in pointer.deallocate() }
        )

        let data = try buffer.dataBytes()
        try buffer.withUnsafeMutableBytes { $0[0] = 9 }
        #expect(Array(data) == [4, 5, 6])

        let empty = try CMBlockBuffer(capacity: 0)
        #expect(throws: CMBlockBufferError.invalidLength(0)) {
            _ = try empty.dataBytes()
        }
        let malformed = MalformedBlockBufferView(owner: empty)
        #expect(throws: CMBlockBufferError.invalidRange(
            lowerBound: 0,
            upperBound: 1,
            validLowerBound: 0,
            validUpperBound: 0
        )) {
            _ = try malformed.dataBytes()
        }
    }

    private func makeImageSample(
        readiness: CMSampleBufferDataReadiness,
        handler: CMSampleBufferMakeDataReadyHandler?
    ) throws -> (
        sample: CMImageSampleBuffer,
        image: RemainingSurfacePixelBuffer
    ) {
        let dimensions = try CVPixelDimensions(width: 1, height: 1)
        let image = try CVPackedPixelBuffer(
            dimensions: dimensions,
            pixelFormat: .bgra32,
            bytesPerPixel: 4,
            bytesPerRow: 4
        )
        let format = CMImmutableVideoFormatDescription(
            dimensions: dimensions,
            pixelFormat: .bgra32
        )
        let timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: .zero,
            decodeTimeStamp: .invalid
        )
        let sample = try CMImageSampleBuffer(
            imageBuffer: image,
            formatDescription: format,
            timing: [timing],
            dataReadiness: readiness,
            makeDataReadyHandler: handler
        )
        return (sample, image)
    }
}

private final class TestClockSource: CMClockSource, Sendable {
    private let storedTime: Mutex<CMTime>
    let mightDrift = false
    let referenceTime = CMTime(value: 1_000, timescale: 1)

    init(time: CMTime) {
        storedTime = Mutex(time)
    }

    func currentTime() throws(CMClockError) -> CMTime {
        storedTime.withLock { $0 }
    }

    func setTime(_ time: CMTime) {
        storedTime.withLock { $0 = time }
    }

    func anchorTime() throws(CMClockError) -> (
        clockTime: CMTime,
        referenceClockTime: CMTime
    ) {
        (storedTime.withLock { $0 }, referenceTime)
    }
}

private actor ReadinessGate {
    private var started = false
    private var continuation: CheckedContinuation<Void, Never>?

    func suspend() async {
        started = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func hasStarted() -> Bool {
        started
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

private final class QueueHolder: Sendable {
    private let storage = Mutex<CMBufferQueue<TimedQueueValue>?>(nil)

    var queue: CMBufferQueue<TimedQueueValue>? {
        get { storage.withLock { $0 } }
        set { storage.withLock { $0 = newValue } }
    }
}

private final class SimpleQueueHolder: Sendable {
    private let storage = Mutex<CMSimpleQueue<ReentrantRelease>?>(nil)

    var queue: CMSimpleQueue<ReentrantRelease>? {
        get { storage.withLock { $0 } }
        set { storage.withLock { $0 = newValue } }
    }
}

private final class ReentrantRelease: Sendable {
    private let onRelease: @Sendable () -> Void

    init(onRelease: @escaping @Sendable () -> Void) {
        self.onRelease = onRelease
    }

    deinit {
        onRelease()
    }
}

private struct MalformedBlockBufferView: CMBlockBufferProtocol {
    let owner: CMBlockBuffer
    let startIndex = 0
    let endIndex = 1
}

private typealias RemainingSurfacePixelBuffer = CVPackedPixelBuffer

private struct TimedQueueValue: Sendable, Equatable {
    let presentationTimeStamp: CMTime
    let duration: CMTime
    let size: Int
    let isReady: Bool
}

private struct ByteArrayAttachmentAdapter: CMAttachmentPlatformAdapter {
    func portableValue(
        from value: borrowing [UInt8]
    ) -> CMAttachmentValue {
        value.withUnsafeBytes { bytes in
            .bytes(CMAttachmentBytes(copying: bytes))
        }
    }

    func platformValue(
        from value: CMAttachmentValue
    ) throws -> [UInt8] {
        guard case .bytes(let bytes) = value else {
            throw ByteArrayAttachmentAdapterError.incompatibleValue
        }
        return bytes.withUnsafeBytes { rawBytes in
            var result: [UInt8] = []
            result.reserveCapacity(rawBytes.count)
            for byte in rawBytes {
                result.append(byte)
            }
            return result
        }
    }
}

private enum ByteArrayAttachmentAdapterError: Error {
    case incompatibleValue
}
