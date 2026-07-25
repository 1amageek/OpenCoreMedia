import Synchronization

public final class CMBufferQueue<Element: Sendable>: Sendable {
    private final class Entry: Sendable {
        let element: Element
        let duration: CMTime
        let size: Int

        init(element: Element, duration: CMTime, size: Int) {
            self.element = element
            self.duration = duration
            self.size = size
        }
    }

    private struct State: Sendable {
        var entries: [Entry?]
        var headIndex: Int
        var activeCount: Int
        var containsEndOfData: Bool
        var numericDuration: CMTime
        var invalidDurationCount: Int
        var positiveInfinityCount: Int
        var negativeInfinityCount: Int
        var totalSize: Int
        var revision: UInt64
    }

    private let maximumCapacity: Int
    private let callbacks: CMBufferQueueCallbacks<Element>
    private let state: CMStateLock<State>

    public init(
        capacity: Int,
        callbacks: CMBufferQueueCallbacks<Element>
    ) throws(CMBufferQueueError) {
        guard capacity > 0 else {
            throw .invalidCapacity(capacity)
        }
        maximumCapacity = capacity
        self.callbacks = callbacks
        state = CMStateLock(State(
            entries: [],
            headIndex: 0,
            activeCount: 0,
            containsEndOfData: false,
            numericDuration: .zero,
            invalidDurationCount: 0,
            positiveInfinityCount: 0,
            negativeInfinityCount: 0,
            totalSize: 0,
            revision: 0
        ))
    }

    public var count: Int {
        state.withLock { $0.activeCount }
    }

    public var isEmpty: Bool {
        count == 0
    }

    public var containsEndOfData: Bool {
        state.withLock { $0.containsEndOfData }
    }

    public var isAtEndOfData: Bool {
        state.withLock {
            $0.containsEndOfData && $0.activeCount == 0
        }
    }

    public var duration: CMTime {
        state.withLock { aggregateDuration($0) }
    }

    public var totalSize: Int {
        state.withLock { $0.totalSize }
    }

    public func enqueue(
        _ element: Element
    ) throws(CMBufferQueueError) {
        let duration = callbacks.duration(element)
        let size = callbacks.size?(element) ?? 0
        guard size >= 0 else {
            throw .invalidSize(size)
        }
        let entry = Entry(
            element: element,
            duration: duration,
            size: size
        )

        while true {
            let snapshot = try state.withLock {
                state throws(CMBufferQueueError) -> (
                    revision: UInt64,
                    entries: [Entry]
                ) in
                guard !state.containsEndOfData else {
                    throw .enqueueAfterEndOfData
                }
                guard state.activeCount < maximumCapacity else {
                    throw .queueIsFull
                }
                let activeEntries = state.entries[state.headIndex...]
                    .compactMap { $0 }
                return (state.revision, activeEntries)
            }

            let insertionOffset: Int
            if let compare = callbacks.compare {
                insertionOffset = snapshot.entries.firstIndex {
                    compare(entry.element, $0.element)
                } ?? snapshot.entries.endIndex
            } else {
                insertionOffset = snapshot.entries.endIndex
            }

            let committed = try state.withLock {
                state throws(CMBufferQueueError) -> Bool in
                guard state.revision == snapshot.revision else {
                    return false
                }
                guard !state.containsEndOfData else {
                    throw .enqueueAfterEndOfData
                }
                guard state.activeCount < maximumCapacity else {
                    throw .queueIsFull
                }
                let (nextSize, sizeOverflow) =
                    state.totalSize.addingReportingOverflow(size)
                guard !sizeOverflow else {
                    throw .totalSizeOverflow
                }

                compactStorageIfNeeded(&state)
                let insertionIndex = state.headIndex + insertionOffset
                state.entries.insert(entry, at: insertionIndex)
                state.activeCount += 1
                addDuration(duration, to: &state)
                state.totalSize = nextSize
                state.revision &+= 1
                return true
            }
            if committed {
                return
            }
        }
    }

    public func dequeue() -> Element? {
        removeHead()
    }

    public func dequeueIfDataReady() -> Element? {
        guard let isDataReady = callbacks.isDataReady else {
            return removeHead()
        }

        while true {
            guard let snapshot = headSnapshot() else {
                return nil
            }
            guard isDataReady(snapshot.entry.element) else {
                return nil
            }
            let removed = state.withLock { state -> Entry? in
                guard state.revision == snapshot.revision,
                      state.headIndex < state.entries.count,
                      state.entries[state.headIndex] === snapshot.entry
                else {
                    return nil
                }
                return removeHeadLocked(&state)
            }
            if let removed {
                return removed.element
            }
        }
    }

    public func head() -> Element? {
        headSnapshot()?.entry.element
    }

    public func markEndOfData() {
        state.withLock {
            $0.containsEndOfData = true
            $0.revision &+= 1
        }
    }

    public func reset() {
        let removedEntries = state.withLock { state -> [Entry?] in
            let removed = state.entries
            state.entries = []
            state.headIndex = 0
            state.activeCount = 0
            state.containsEndOfData = false
            state.numericDuration = .zero
            state.invalidDurationCount = 0
            state.positiveInfinityCount = 0
            state.negativeInfinityCount = 0
            state.totalSize = 0
            state.revision &+= 1
            return removed
        }
        _fixLifetime(removedEntries)
    }

    public func firstDecodeTimeStamp() -> CMTime {
        guard let timestamp = callbacks.decodeTimeStamp,
              let element = head()
        else {
            return .invalid
        }
        return timestamp(element)
    }

    public func firstPresentationTimeStamp() -> CMTime {
        guard let timestamp = callbacks.presentationTimeStamp,
              let element = head()
        else {
            return .invalid
        }
        return timestamp(element)
    }

    private func headSnapshot() -> (
        revision: UInt64,
        entry: Entry
    )? {
        state.withLock { state in
            guard state.headIndex < state.entries.count,
                  let entry = state.entries[state.headIndex]
            else {
                return nil
            }
            return (state.revision, entry)
        }
    }

    private func removeHead() -> Element? {
        let removed = state.withLock { state in
            removeHeadLocked(&state)
        }
        return removed?.element
    }

    private func removeHeadLocked(_ state: inout State) -> Entry? {
        guard state.headIndex < state.entries.count,
              let entry = state.entries[state.headIndex]
        else {
            return nil
        }
        state.entries[state.headIndex] = nil
        state.headIndex += 1
        state.activeCount -= 1
        removeDuration(entry.duration, from: &state)
        state.totalSize -= entry.size
        state.revision &+= 1
        if state.activeCount == 0 {
            state.entries.removeAll(keepingCapacity: true)
            state.headIndex = 0
        }
        return entry
    }

    private func compactStorageIfNeeded(_ state: inout State) {
        guard state.headIndex > 64,
              state.headIndex >= state.entries.count - state.headIndex
        else {
            return
        }
        state.entries = Array(state.entries[state.headIndex...])
        state.headIndex = 0
    }

    private func aggregateDuration(_ state: State) -> CMTime {
        if state.invalidDurationCount > 0
            || (
                state.positiveInfinityCount > 0
                    && state.negativeInfinityCount > 0
            )
        {
            return .invalid
        }
        if state.positiveInfinityCount > 0 {
            return .positiveInfinity
        }
        if state.negativeInfinityCount > 0 {
            return .negativeInfinity
        }
        return state.numericDuration
    }

    private func addDuration(_ duration: CMTime, to state: inout State) {
        if duration.isPositiveInfinity {
            state.positiveInfinityCount += 1
        } else if duration.isNegativeInfinity {
            state.negativeInfinityCount += 1
        } else if duration.isNumeric {
            state.numericDuration =
                state.numericDuration + normalizedEpoch(duration)
        } else {
            state.invalidDurationCount += 1
        }
    }

    private func removeDuration(
        _ duration: CMTime,
        from state: inout State
    ) {
        if duration.isPositiveInfinity {
            state.positiveInfinityCount -= 1
        } else if duration.isNegativeInfinity {
            state.negativeInfinityCount -= 1
        } else if duration.isNumeric {
            state.numericDuration =
                state.numericDuration - normalizedEpoch(duration)
        } else {
            state.invalidDurationCount -= 1
        }
        if state.activeCount == 0 {
            state.numericDuration = .zero
            state.invalidDurationCount = 0
            state.positiveInfinityCount = 0
            state.negativeInfinityCount = 0
        }
    }

    private func normalizedEpoch(_ duration: CMTime) -> CMTime {
        CMTime(
            value: duration.value,
            timescale: duration.timescale,
            flags: duration.flags,
            epoch: 0
        )
    }

}
