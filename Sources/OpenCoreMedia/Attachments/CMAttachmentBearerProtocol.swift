public protocol CMAttachmentBearerProtocol:
    AnyObject,
    CMPlatformConcurrencyContract
{
    var attachments: CMAttachmentBearerAttachments { get }

    func propagateAttachments<
        Destination: CMAttachmentBearerProtocol
    >(to destination: borrowing Destination)
}

extension CMAttachmentBearerProtocol {
    public func propagateAttachments<
        Destination: CMAttachmentBearerProtocol
    >(to destination: borrowing Destination) {
        CMPropagateAttachments(self, destination: destination)
    }
}
