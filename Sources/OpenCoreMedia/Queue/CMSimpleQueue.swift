import Synchronization

public final class CMSimpleQueue<Element: Sendable>: Sendable {
    private struct State: Sendable {
        var incoming: [Element]
        var outgoing: [Element]
        var count: Int
    }

    private let maximumCapacity: Int
    private let state: CMStateLock<State>

    public init(capacity: Int) throws(CMSimpleQueueError) {
        guard capacity > 0,
              Int32(exactly: capacity) != nil
        else {
            throw .invalidCapacity(capacity)
        }
        maximumCapacity = capacity
        state = CMStateLock(State(
            incoming: [],
            outgoing: [],
            count: 0
        ))
    }

    public var capacity: Int {
        maximumCapacity
    }

    public var count: Int {
        state.withLock { $0.count }
    }

    public var fullness: Float {
        Float(count) / Float(maximumCapacity)
    }

    public func enqueue(
        _ element: Element
    ) throws(CMSimpleQueueError) {
        try state.withLock { state throws(CMSimpleQueueError) in
            guard state.count < maximumCapacity else {
                throw .queueIsFull
            }
            state.incoming.append(element)
            state.count += 1
        }
    }

    public func dequeue() -> Element? {
        state.withLock { state in
            prepareOutgoing(&state)
            guard let element = state.outgoing.popLast() else {
                return nil
            }
            state.count -= 1
            return element
        }
    }

    public func head() -> Element? {
        state.withLock { state in
            prepareOutgoing(&state)
            return state.outgoing.last
        }
    }

    public func reset() {
        let removed = state.withLock {
            state -> (incoming: [Element], outgoing: [Element]) in
            let removed = (state.incoming, state.outgoing)
            state.incoming = []
            state.outgoing = []
            state.count = 0
            return removed
        }
        _fixLifetime(removed)
    }

    private func prepareOutgoing(_ state: inout State) {
        guard state.outgoing.isEmpty else {
            return
        }
        state.outgoing.reserveCapacity(state.incoming.count)
        while let element = state.incoming.popLast() {
            state.outgoing.append(element)
        }
    }
}
