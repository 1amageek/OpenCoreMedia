public protocol CMFormatDescription: AnyObject, Sendable {
    var mediaType: CMMediaType { get }
    var mediaSubtype: UInt32 { get }
}
