import Foundation
@_spi(OpenCoreMediaFoundation) import OpenCoreMedia

extension CMBlockBufferProtocol {
    /// Materializes this represented range into Foundation-owned storage.
    ///
    /// This is an explicit full-payload copy boundary. Use scoped block-buffer
    /// borrows when a copy is not required.
    public func dataBytes() throws -> Data {
        let range = try validatedDataRange()
        guard !range.isEmpty else {
            throw CMBlockBufferError.invalidLength(0)
        }
        var data = Data(count: range.count)
        try data.withUnsafeMutableBytes { destination in
            try copyDataBytes(to: destination)
        }
        return data
    }
}
