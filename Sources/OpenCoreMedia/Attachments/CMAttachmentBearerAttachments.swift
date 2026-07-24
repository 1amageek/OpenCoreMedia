public struct CMAttachmentBearerAttachments:
    CMPlatformConcurrencyContract
{
    public enum Mode: UInt32, Sendable, Hashable {
        case shouldNotPropagate = 0
        case shouldPropagate = 1
    }

    public enum Value: Sendable, Equatable {
        case shouldNotPropagate(CMAttachmentValue)
        case shouldPropagate(CMAttachmentValue)

        public init(
            value: CMAttachmentValue,
            mode: Mode
        ) {
            switch mode {
            case .shouldNotPropagate:
                self = .shouldNotPropagate(value)
            case .shouldPropagate:
                self = .shouldPropagate(value)
            }
        }

        public var value: CMAttachmentValue {
            switch self {
            case .shouldNotPropagate(let value),
                 .shouldPropagate(let value):
                value
            }
        }

        public var mode: Mode {
            switch self {
            case .shouldNotPropagate:
                .shouldNotPropagate
            case .shouldPropagate:
                .shouldPropagate
            }
        }
    }

    private let storage: CMAttachmentStorageReference

    public init() {
        storage = CMAttachmentStorageReference()
    }

    public subscript(key: String) -> Value? {
        get {
            storage.attachment(for: key)
        }
        nonmutating set {
            if let newValue {
                storage.setAttachment(newValue, for: key)
            } else {
                storage.removeAttachment(for: key)
            }
        }
    }

    public subscript(key: CMAttachmentKey) -> Value? {
        get {
            self[key.rawValue]
        }
        nonmutating set {
            self[key.rawValue] = newValue
        }
    }

    public var propagated: [String: CMAttachmentValue] {
        storage.attachments(for: .shouldPropagate)
    }

    public var nonPropagated: [String: CMAttachmentValue] {
        storage.attachments(for: .shouldNotPropagate)
    }

    public func merge(
        _ attachments: [String: CMAttachmentValue],
        mode: Mode
    ) {
        storage.setAttachments(attachments, mode: mode)
    }

    public func removeAll() {
        storage.removeAllAttachments()
    }
}
