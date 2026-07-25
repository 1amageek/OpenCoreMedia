import OpenCoreMedia
import Testing

@Suite("Core Media attachment smoke")
struct CMAttachmentSmokeTests {
    @Test("Set, replace, filter, and remove preserve value and mode")
    func storageOperations() {
        let bearer = TestAttachmentBearer()
        let firstKey = CMAttachmentKey(rawValue: "test.first")
        let secondKey = CMAttachmentKey(rawValue: "test.second")

        #expect(CMGetAttachment(bearer, key: firstKey) == nil)
        #expect(CMCopyDictionaryOfAttachments(
            target: bearer,
            attachmentMode: .shouldPropagate
        ) == nil)

        CMSetAttachment(
            bearer,
            key: firstKey,
            value: .integer(41),
            attachmentMode: .shouldNotPropagate
        )
        #expect(CMGetAttachment(bearer, key: firstKey) == CMAttachment(
            value: .integer(41),
            mode: .shouldNotPropagate
        ))

        CMSetAttachment(
            bearer,
            key: firstKey,
            value: .string("replacement"),
            attachmentMode: .shouldPropagate
        )
        CMSetAttachments(
            bearer,
            attachments: [secondKey: .boolean(true)],
            attachmentMode: .shouldNotPropagate
        )

        #expect(CMCopyDictionaryOfAttachments(
            target: bearer,
            attachmentMode: .shouldPropagate
        ) == [firstKey: .string("replacement")])
        #expect(CMCopyDictionaryOfAttachments(
            target: bearer,
            attachmentMode: .shouldNotPropagate
        ) == [secondKey: .boolean(true)])

        CMRemoveAttachment(bearer, key: firstKey)
        #expect(CMGetAttachment(bearer, key: firstKey) == nil)
        #expect(CMGetAttachment(bearer, key: secondKey) != nil)

        CMRemoveAllAttachments(bearer)
        #expect(CMGetAttachment(bearer, key: secondKey) == nil)
    }

    @Test("Propagation snapshots only propagatable values")
    func propagation() {
        let source = TestAttachmentBearer()
        let destination = TestAttachmentBearer()
        let propagatedKey = CMAttachmentKey(rawValue: "test.propagated")
        let localKey = CMAttachmentKey(rawValue: "test.local")
        let destinationKey = CMAttachmentKey(rawValue: "test.destination")

        CMSetAttachment(
            source,
            key: propagatedKey,
            value: .unsignedInteger(73),
            attachmentMode: .shouldPropagate
        )
        CMSetAttachment(
            source,
            key: localKey,
            value: .floatingPoint(1.5),
            attachmentMode: .shouldNotPropagate
        )
        CMSetAttachment(
            destination,
            key: destinationKey,
            value: .string("preserved"),
            attachmentMode: .shouldNotPropagate
        )

        CMPropagateAttachments(source, destination: destination)

        #expect(CMGetAttachment(
            destination,
            key: propagatedKey
        ) == CMAttachment(
            value: .unsignedInteger(73),
            mode: .shouldPropagate
        ))
        #expect(CMGetAttachment(destination, key: localKey) == nil)
        #expect(CMGetAttachment(
            destination,
            key: destinationKey
        ) == CMAttachment(
            value: .string("preserved"),
            mode: .shouldNotPropagate
        ))

        CMSetAttachment(
            source,
            key: propagatedKey,
            value: .unsignedInteger(99),
            attachmentMode: .shouldPropagate
        )
        #expect(CMGetAttachment(
            destination,
            key: propagatedKey
        )?.value == .unsignedInteger(73))
    }

    @Test("Swift overlay supports keyed mutation and propagation")
    func swiftOverlay() {
        let source = TestAttachmentBearer()
        let destination = TestAttachmentBearer()

        source.attachments["test.propagated"] =
            .shouldPropagate(.integer(11))
        source.attachments["test.local"] =
            .shouldNotPropagate(.string("local"))

        #expect(
            source.attachments["test.propagated"]?.value
                == .integer(11)
        )
        #expect(source.attachments.propagated == [
            "test.propagated": .integer(11)
        ])
        #expect(source.attachments.nonPropagated == [
            "test.local": .string("local")
        ])

        source.propagateAttachments(to: destination)

        #expect(
            destination.attachments["test.propagated"]?.mode
                == .shouldPropagate
        )
        #expect(destination.attachments["test.local"] == nil)

        source.attachments["test.local"] = nil
        #expect(source.attachments.nonPropagated.isEmpty)
        source.attachments.removeAll()
        #expect(source.attachments.propagated.isEmpty)
    }

    @Test("Concurrent snapshots and propagation remain race-safe")
    func concurrentSnapshotsAndPropagation() async throws {
        let source = TestAttachmentBearer()
        let destination = TestAttachmentBearer()

        await withTaskGroup(of: Void.self) { group in
            for worker in 0..<4 {
                group.addTask {
                    let key = CMAttachmentKey(
                        rawValue: "test.worker.\(worker)"
                    )
                    for value in 0..<50 {
                        CMSetAttachment(
                            source,
                            key: key,
                            value: .integer(Int64(value)),
                            attachmentMode: .shouldPropagate
                        )
                        _ = CMGetAttachment(source, key: key)
                        _ = CMCopyDictionaryOfAttachments(
                            target: source,
                            attachmentMode: .shouldPropagate
                        )
                        CMPropagateAttachments(
                            source,
                            destination: destination
                        )
                    }
                }
            }
            await group.waitForAll()
        }

        CMPropagateAttachments(source, destination: destination)
        for worker in 0..<4 {
            let key = CMAttachmentKey(
                rawValue: "test.worker.\(worker)"
            )
            #expect(CMGetAttachment(source, key: key)?.value == .integer(49))
            #expect(
                CMGetAttachment(destination, key: key)?.value == .integer(49)
            )
        }
    }
}

private final class TestAttachmentBearer:
    CMAttachmentBearerProtocol
{
    let attachments = CMAttachmentBearerAttachments()
}
