public protocol CMAttachmentStorageBearerProtocol:
    AnyObject,
    CMPlatformConcurrencyContract
{
    var attachments: CMAttachmentBearerAttachments { get }
}

public protocol CMAttachmentBearerProtocol:
    CMAttachmentStorageBearerProtocol,
    CMPlatformConcurrencyContract
{}

extension CMAttachmentBearerProtocol {
    public func propagateAttachments<
        Destination: CMAttachmentBearerProtocol
    >(to destination: borrowing Destination) {
        CMPropagateAttachments(self, destination: destination)
    }
}
