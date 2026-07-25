import Synchronization

final class CMBlockBufferMemoryLease: Sendable {
    private struct State: Sendable {
        var pointerAddress: UInt?
        var isAllocating = false
        var activeReaders = 0
        var isWriting = false
    }

    private enum PointerResolution {
        case existing(UInt)
        case allocate
    }

    private let state: CMStateLock<State>
    let byteCount: Int
    private let allocator: CMBlockBuffer.CustomBlockAllocator?
    private let deallocator: CMBlockBuffer.CustomBlockDeallocator

    init(
        pointer: UnsafeMutableRawPointer,
        byteCount: Int,
        deallocator: @escaping CMBlockBuffer.CustomBlockDeallocator
    ) {
        state = CMStateLock(State(pointerAddress: UInt(bitPattern: pointer)))
        self.byteCount = byteCount
        allocator = nil
        self.deallocator = deallocator
    }

    init(
        deferredByteCount: Int,
        allocator: @escaping CMBlockBuffer.CustomBlockAllocator,
        deallocator: @escaping CMBlockBuffer.CustomBlockDeallocator
    ) {
        state = CMStateLock(State(pointerAddress: nil))
        byteCount = deferredByteCount
        self.allocator = allocator
        self.deallocator = deallocator
    }

    deinit {
        let pointerAddress = state.withLock { $0.pointerAddress }
        if let pointerAddress,
           let pointer = UnsafeMutableRawPointer(bitPattern: pointerAddress)
        {
            deallocator(pointer, byteCount)
        }
    }

    func assureMemory() throws(CMBlockBufferError) {
        _ = try assuredPointer()
    }

    func withReadBytes<R>(
        in range: Range<Int>,
        _ body: (UnsafeRawBufferPointer) throws -> R
    ) throws -> R {
        let pointer = try assuredPointer()
        try beginRead()
        defer {
            endRead()
        }
        let bytes = UnsafeRawBufferPointer(
            start: pointer.advanced(by: range.lowerBound),
            count: range.count
        )
        return try body(bytes)
    }

    func withWriteBytes<R>(
        in range: Range<Int>,
        _ body: (UnsafeMutableRawBufferPointer) throws -> R
    ) throws -> R {
        let pointer = try assuredPointer()
        try beginWrite()
        defer {
            endWrite()
        }
        let bytes = UnsafeMutableRawBufferPointer(
            start: pointer.advanced(by: range.lowerBound),
            count: range.count
        )
        return try body(bytes)
    }

    func overlaps(
        _ externalBytes: UnsafeRawBufferPointer,
        in range: Range<Int>
    ) throws(CMBlockBufferError) -> Bool {
        guard !externalBytes.isEmpty,
              !range.isEmpty,
              let externalBaseAddress = externalBytes.baseAddress
        else {
            return false
        }

        let pointer = try assuredPointer()
        let leaseStart = UInt(
            bitPattern: pointer.advanced(by: range.lowerBound)
        )
        let externalStart = UInt(bitPattern: externalBaseAddress)
        let (leaseEnd, leaseOverflow) =
            leaseStart.addingReportingOverflow(UInt(range.count))
        let (externalEnd, externalOverflow) =
            externalStart.addingReportingOverflow(
                UInt(externalBytes.count)
            )

        guard !leaseOverflow, !externalOverflow else {
            return true
        }
        return leaseStart < externalEnd
            && externalStart < leaseEnd
    }

    func copyBytes(
        in range: Range<Int>,
        to destination: UnsafeMutableRawBufferPointer
    ) throws(CMBlockBufferError) {
        let pointer = try assuredPointer()
        try beginRead()
        defer {
            endRead()
        }
        destination.copyMemory(from: UnsafeRawBufferPointer(
            start: pointer.advanced(by: range.lowerBound),
            count: range.count
        ))
    }

    func replaceBytes(
        in range: Range<Int>,
        with source: UnsafeRawBufferPointer
    ) throws(CMBlockBufferError) {
        let pointer = try assuredPointer()
        try beginWrite()
        defer {
            endWrite()
        }
        UnsafeMutableRawBufferPointer(
            start: pointer.advanced(by: range.lowerBound),
            count: range.count
        ).copyMemory(from: source)
    }

    func fillBytes(
        in range: Range<Int>,
        with fillByte: UInt8
    ) throws(CMBlockBufferError) {
        let pointer = try assuredPointer()
        try beginWrite()
        defer {
            endWrite()
        }
        _ = UnsafeMutableRawBufferPointer(
            start: pointer.advanced(by: range.lowerBound),
            count: range.count
        ).initializeMemory(
            as: UInt8.self,
            repeating: fillByte
        )
    }

    private func assuredPointer()
        throws(CMBlockBufferError) -> UnsafeMutableRawPointer
    {
        let resolution = try state.withLock {
            state throws(CMBlockBufferError) -> PointerResolution in
            if let pointerAddress = state.pointerAddress {
                return .existing(pointerAddress)
            }
            guard !state.isAllocating else {
                throw .allocationInProgress
            }
            state.isAllocating = true
            return .allocate
        }

        switch resolution {
        case .existing(let pointerAddress):
            guard let pointer = UnsafeMutableRawPointer(
                bitPattern: pointerAddress
            ) else {
                throw .storageUnavailable
            }
            return pointer
        case .allocate:
            guard let allocator,
                  let allocatedPointer = allocator(byteCount)
            else {
                state.withLock { state in
                    state.isAllocating = false
                }
                throw .allocationFailed(length: byteCount)
            }
            state.withLock { state in
                precondition(
                    state.isAllocating && state.pointerAddress == nil
                )
                state.pointerAddress = UInt(bitPattern: allocatedPointer)
                state.isAllocating = false
            }
            return allocatedPointer
        }
    }

    private func beginRead() throws(CMBlockBufferError) {
        try state.withLock { state throws(CMBlockBufferError) in
            guard !state.isWriting else {
                throw .concurrentAccessConflict
            }
            state.activeReaders += 1
        }
    }

    private func endRead() {
        state.withLock { state in
            precondition(state.activeReaders > 0)
            state.activeReaders -= 1
        }
    }

    private func beginWrite() throws(CMBlockBufferError) {
        try state.withLock { state throws(CMBlockBufferError) in
            guard !state.isWriting, state.activeReaders == 0 else {
                throw .concurrentAccessConflict
            }
            state.isWriting = true
        }
    }

    private func endWrite() {
        state.withLock { state in
            precondition(state.isWriting)
            state.isWriting = false
        }
    }
}
