import Synchronization

final class CMStateLock<State: Sendable>: Sendable {
    private let state: Mutex<State>

    init(_ initialState: sending State) {
        state = Mutex(initialState)
    }

    func withLock<Result: ~Copyable, E: Error>(
        _ body: (inout sending State) throws(E) -> sending Result
    ) throws(E) -> sending Result {
        try state.withLock(body)
    }
}
