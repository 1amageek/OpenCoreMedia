public struct CMAttachmentBytes: Sendable, Equatable {
    private let storage: [UInt8]

    public init(_ bytes: [UInt8]) {
        storage = bytes
    }

    /// Creates owned attachment bytes by copying the borrowed input.
    public init(copying bytes: UnsafeRawBufferPointer) {
        var copied = [UInt8](repeating: 0, count: bytes.count)
        copied.withUnsafeMutableBytes { destination in
            guard !bytes.isEmpty else {
                return
            }
            destination.copyMemory(from: bytes)
        }
        storage = copied
    }

    public var count: Int {
        storage.count
    }

    public var isEmpty: Bool {
        storage.isEmpty
    }

    /// Borrows the owned bytes for the duration of `body`.
    ///
    /// The buffer, its base address, and every derived pointer are valid only
    /// during `body`. Do not return or store those pointers.
    public func withUnsafeBytes<R>(
        _ body: (UnsafeRawBufferPointer) throws -> R
    ) rethrows -> R {
        try storage.withUnsafeBytes(body)
    }
}
