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

    func overlaps(
        _ externalBytes: UnsafeRawBufferPointer,
        in range: Range<Int>
    ) -> Bool {
        guard !externalBytes.isEmpty,
              !range.isEmpty,
              let externalBaseAddress = externalBytes.baseAddress
        else {
            return false
        }

        let leaseStart = UInt(
            bitPattern: pointer.advanced(by: range.lowerBound)
        )
        let externalStart = UInt(bitPattern: externalBaseAddress)
        let (leaseEnd, leaseOverflow) = leaseStart.addingReportingOverflow(
            UInt(range.count)
        )
        let (externalEnd, externalOverflow) =
            externalStart.addingReportingOverflow(
                UInt(externalBytes.count)
            )

        guard !leaseOverflow, !externalOverflow else {
            return true
        }
        return leaseStart < externalEnd && externalStart < leaseEnd
    }
}
