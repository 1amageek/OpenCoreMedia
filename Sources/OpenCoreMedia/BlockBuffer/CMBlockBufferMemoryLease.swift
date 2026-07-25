final class CMBlockBufferMemoryLease {
    private let pointer: UnsafeMutableRawPointer
    let byteCount: Int
    private let deallocator: CMBlockBuffer.CustomBlockDeallocator

    init(
        pointer: UnsafeMutableRawPointer,
        byteCount: Int,
        deallocator: @escaping CMBlockBuffer.CustomBlockDeallocator
    ) {
        self.pointer = pointer
        self.byteCount = byteCount
        self.deallocator = deallocator
    }

    deinit {
        deallocator(pointer, byteCount)
    }

    func withReadBytes<R>(
        in range: Range<Int>,
        _ body: (UnsafeRawBufferPointer) throws -> R
    ) rethrows -> R {
        let bytes = UnsafeRawBufferPointer(
            start: pointer.advanced(by: range.lowerBound),
            count: range.count
        )
        return try body(bytes)
    }

    func withWriteBytes<R>(
        in range: Range<Int>,
        _ body: (UnsafeMutableRawBufferPointer) throws -> R
    ) rethrows -> R {
        let bytes = UnsafeMutableRawBufferPointer(
            start: pointer.advanced(by: range.lowerBound),
            count: range.count
        )
        return try body(bytes)
    }
}
