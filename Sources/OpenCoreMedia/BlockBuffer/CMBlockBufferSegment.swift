struct CMBlockBufferSegment {
    let lease: CMBlockBufferMemoryLease
    let leaseRange: Range<Int>

    var count: Int {
        leaseRange.count
    }

    func canMerge(with other: CMBlockBufferSegment) -> Bool {
        lease === other.lease
            && leaseRange.upperBound == other.leaseRange.lowerBound
    }

    func merged(with other: CMBlockBufferSegment) -> CMBlockBufferSegment {
        CMBlockBufferSegment(
            lease: lease,
            leaseRange: leaseRange.lowerBound..<other.leaseRange.upperBound
        )
    }
}
