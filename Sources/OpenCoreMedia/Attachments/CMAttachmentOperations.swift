public func CMGetAttachment<Target: CMAttachmentStorageBearerProtocol>(
    _ target: borrowing Target,
    key: CMAttachmentKey
) -> CMAttachment? {
    target.attachments[key]
}

public func CMCopyDictionaryOfAttachments<
    Target: CMAttachmentStorageBearerProtocol
>(
    target: borrowing Target,
    attachmentMode: CMAttachmentMode
) -> [CMAttachmentKey: CMAttachmentValue]? {
    let values: [String: CMAttachmentValue]
    switch attachmentMode {
    case .shouldNotPropagate:
        values = target.attachments.nonPropagated
    case .shouldPropagate:
        values = target.attachments.propagated
    }
    guard !values.isEmpty else {
        return nil
    }
    var keyedValues: [CMAttachmentKey: CMAttachmentValue] = [:]
    keyedValues.reserveCapacity(values.count)
    for (key, value) in values {
        keyedValues[CMAttachmentKey(rawValue: key)] = value
    }
    return keyedValues
}

public func CMSetAttachment<Target: CMAttachmentStorageBearerProtocol>(
    _ target: borrowing Target,
    key: CMAttachmentKey,
    value: CMAttachmentValue,
    attachmentMode: CMAttachmentMode
) {
    target.attachments[key] = CMAttachment(
        value: value,
        mode: attachmentMode
    )
}

public func CMSetAttachments<Target: CMAttachmentStorageBearerProtocol>(
    _ target: borrowing Target,
    attachments: [CMAttachmentKey: CMAttachmentValue],
    attachmentMode: CMAttachmentMode
) {
    var stringAttachments: [String: CMAttachmentValue] = [:]
    stringAttachments.reserveCapacity(attachments.count)
    for (key, value) in attachments {
        stringAttachments[key.rawValue] = value
    }
    target.attachments.merge(
        stringAttachments,
        mode: attachmentMode
    )
}

public func CMRemoveAttachment<Target: CMAttachmentStorageBearerProtocol>(
    _ target: borrowing Target,
    key: CMAttachmentKey
) {
    target.attachments[key] = nil
}

public func CMRemoveAllAttachments<Target: CMAttachmentStorageBearerProtocol>(
    _ target: borrowing Target
) {
    target.attachments.removeAll()
}

public func CMPropagateAttachments<
    Source: CMAttachmentStorageBearerProtocol,
    Destination: CMAttachmentStorageBearerProtocol
>(
    _ source: borrowing Source,
    destination: borrowing Destination
) {
    // Snapshot the source before touching the destination. Implementations may
    // use independent locks, so propagation never nests attachment locks.
    let propagated = source.attachments.propagated
    destination.attachments.merge(
        propagated,
        mode: .shouldPropagate
    )
}
