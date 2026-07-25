public struct CMSampleAttachmentDictionary:
    Sequence,
    CMPlatformConcurrencyContract
{
    public typealias Element = Dictionary<
        String,
        CMAttachmentValue
    >.Element
    public typealias Iterator = Dictionary<
        String,
        CMAttachmentValue
    >.Iterator

    private let storage: CMSampleAttachmentDictionaryStorage

    init(storage: CMSampleAttachmentDictionaryStorage) {
        self.storage = storage
    }

    public var dictionaryRepresentation:
        [String: CMAttachmentValue]
    {
        storage.snapshot()
    }

    public var count: Int {
        storage.count
    }

    public var isEmpty: Bool {
        storage.isEmpty
    }

    public func makeIterator() -> Iterator {
        storage.snapshot().makeIterator()
    }

    public subscript(
        rawAttachment key: String
    ) -> CMAttachmentValue? {
        get {
            storage.value(for: key)
        }
        nonmutating set {
            storage.setValue(newValue, for: key)
        }
    }

    public subscript(
        key: CMSampleAttachmentKey
    ) -> CMAttachmentValue? {
        get {
            self[rawAttachment: key.rawValue]
        }
        nonmutating set {
            self[rawAttachment: key.rawValue] = newValue
        }
    }

    public func booleanValue(
        for key: CMSampleAttachmentKey
    ) throws(CMSampleAttachmentError) -> Bool? {
        guard let value = self[key] else {
            return nil
        }
        guard case .boolean(let boolean) = value else {
            throw .valueIsNotBoolean(key: key)
        }
        return boolean
    }

    public func setBoolean(
        _ value: Bool,
        for key: CMSampleAttachmentKey
    ) {
        self[key] = .boolean(value)
    }

    public func removeAll() {
        storage.removeAll()
    }
}
