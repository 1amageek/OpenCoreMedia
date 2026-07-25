public enum CMSampleAttachmentError:
    Error,
    Sendable,
    Equatable
{
    case valueIsNotBoolean(key: CMSampleAttachmentKey)
}
