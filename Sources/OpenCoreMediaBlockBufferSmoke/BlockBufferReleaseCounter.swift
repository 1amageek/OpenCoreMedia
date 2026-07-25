import Synchronization

final class OpenCoreMediaBlockBufferReleaseCounter: Sendable {
    private let storedCount = Mutex(0)

    var count: Int {
        storedCount.withLock { $0 }
    }

    func record() {
        storedCount.withLock { $0 += 1 }
    }
}
