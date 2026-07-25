# OpenCoreMedia Design

## Status

This document is the normative design for the package. The package has completed
behavior Smokes for rational time, basic time ranges, immutable video
descriptions, ready image sample buffers, and a contiguous zero-copy block
buffer owner/view path. Segmented block assembly, zero-copy buffer references,
cross-segment copy/fill/replace operations, and explicit contiguous
materialization are also implemented. Buffer-level attachment operations and
timing-copy propagation are implemented. The current image-sample path
additionally provides lazy per-sample attachment dictionaries and their
timing-copy behavior. These milestones are intentionally narrower than Core
Media API compatibility; the remaining sequence below is still required.

## Apple API review

The initial responsibility split was derived from Apple's public documentation,
read with `remark` on 2026-07-24:

- [Core Media](https://developer.apple.com/documentation/coremedia)
- [CMTime](https://developer.apple.com/documentation/coremedia/cmtime)
- [CMTimeRange](https://developer.apple.com/documentation/coremedia/cmtimerange)
- [CMBlockBuffer](https://developer.apple.com/documentation/coremedia/cmblockbuffer-api)
- [CMSampleBuffer](https://developer.apple.com/documentation/coremedia/cmsamplebuffer-api)
- [CMFormatDescription](https://developer.apple.com/documentation/coremedia/cmformatdescription-api)
- [CMSampleTimingInfo](https://developer.apple.com/documentation/coremedia/cmsampletiminginfo)
- [CMClock](https://developer.apple.com/documentation/coremedia/cmclock-api)
- [CMTimebase](https://developer.apple.com/documentation/coremedia/cmtimebase-api)

Apple defines Core Media as the low-level media pipeline beneath AVFoundation.
Its sample buffer carries uniform media samples, timing and size information, a
format description, attachments, and either block data or a Core Video image
buffer. That boundary is preserved.

The second Smoke also inspected the locally installed Xcode beta SDK on
2026-07-24:

- `MacOSX27.0.sdk/System/Library/Frameworks/CoreMedia.framework/Headers/CMTimeRange.h`;
- `MacOSX27.0.sdk/System/Library/Frameworks/CoreMedia.framework/Headers/CMBlockBuffer.h`;
- the public `CoreMedia` symbol graph emitted by
  `swift-symbolgraph-extract`.

The per-sample attachment slice refreshed the macOS 27 SDK symbol graph and read
`CMSampleBufferGetSampleAttachmentsArray(_:createIfNecessary:)` plus the Sample
Attachment Keys documentation with `remark` on 2026-07-25. It also read the
installed `CMSampleBuffer.h` declarations and comments.

The segmented block-buffer slice refreshed that symbol graph on 2026-07-25,
read the installed `CMBlockBuffer.h`, and reviewed `init(capacity:flags:)`,
`init(bufferReference:flags:)`, `append(buffer:deallocator:flags:)`,
`append(bufferReference:flags:)`, `assureBlockMemory()`, `isContiguous`,
`withContiguousStorage`, and `makeContiguous` with `remark`.

The local Swift overlay exposes `CMBlockBufferProtocol`, `CMBlockBuffer.Slice`,
range subscripts, `withContiguousStorage`, `withUnsafeMutableBytes`,
`copyDataBytes`, `replaceDataBytes`, and `fillDataBytes`. OpenCoreMedia follows
those basic usage shapes where the portable ownership model permits it.

## Responsibility

OpenCoreMedia owns:

- rational time values, ranges, mappings, epochs, and rounding;
- media and codec identifiers used by format descriptions;
- immutable format descriptions;
- segmented byte-block ownership and views;
- timed sample buffers;
- sample and buffer attachments;
- sample data readiness, failure, and invalidation;
- clocks, timebases, synchronization, and media queues;
- correlation metadata that survives routing through a media pipeline.

OpenCoreMedia does not own:

- pixel storage layout or pixel-buffer allocation;
- capture-device discovery, permissions, or controls;
- capture graph construction or output backpressure;
- codecs, file readers, or writers;
- recognition, inference, gestures, or Manas conversion;
- concrete operating-system or camera backends.

## Dependency direction

```text
OpenCoreVideo
      ▲
      │ image payload
OpenCoreMedia
      ▲
      │ timing + sample contract
OpenAVFoundation
```

OpenCoreMedia depends on OpenCoreVideo because a `CMSampleBuffer` may contain a
`CVImageBuffer`. OpenCoreVideo must not depend on OpenCoreMedia.

## API layers

### Time

The first implementation surface is:

- `CMTimeValue`, `CMTimeScale`, and `CMTimeEpoch`;
- `CMTimeFlags` and `CMTimeRoundingMethod`;
- `CMTime`, including invalid, indefinite, and infinite values;
- `CMTimeRange` and `CMTimeMapping`;
- arithmetic and scale conversion.

Time arithmetic uses checked integer operations and explicit rounding. Overflow,
invalid epochs, and nonnumeric values follow recorded Apple behavior rather than
falling back to `Double`.

`CMTimeMapping` preserves the distinction between the Swift value initializer
and the validating `CMTimeMappingMake` factories. Range mapping evaluates the
complete affine transform before applying Core Media's nanosecond-scale result
policy, so separately rounded offset and start values cannot introduce a
one-nanosecond drift. Intermediate rational products use checked `Int128`
arithmetic. `CMTimeFoldIntoRange` uses an exact common timescale and a
nonnegative remainder, preserving rational values for times before and after
the fold range.

### Format description

A format description is immutable and contains:

- media type;
- media subtype;
- media-specific structural information;
- typed extensions;
- for video, dimensions and pixel-format information sufficient to validate an
  associated image buffer.

It describes samples but never owns their media payload.

### Block buffer

A block buffer owns or retains one or more memory segments and exposes ranges
without forcing them into contiguous storage. Each segment is a lease plus a
range within that lease. Adjacent ranges from the same lease are coalesced as
metadata; media bytes are not moved. Externally owned segments have exactly-once
release semantics.

`init(capacity:flags:)` creates an empty segment table. Capacity is a
`UInt32`-bounded segment-count hint. The portable implementation bounds eager
reservation so an untrusted but valid large hint cannot force a process-wide
allocation before any segment exists.
`append(buffer:deallocator:flags:)` adds an external lease.
`append(bufferReference:flags:)` and `init(bufferReference:flags:)` snapshot
segment views from another buffer or slice and retain the same leases. Reference
operations accept `.assureMemoryNow`, `.dontOptimizeDepth`, and
`.permitEmptyReference`. The segment table is always flat, so depth suppression
does not require a second representation.
`init(referencing:)` snapshots the current segment table. Later segment appends
to the source therefore do not change an existing reference, while byte
mutations remain visible through every lease-sharing reference.

`CMBlockBuffer.Slice` retains its `owner` plus an absolute logical byte range.
Cross-segment copy, replace, and fill operations iterate the overlapping
segments directly without assembling an intermediate payload or allocating a
temporary segment-view array.

Borrow APIs create raw-buffer views only for the duration of their closure.
Callers must not return or store the raw buffer, its base address, or a derived
pointer. OpenCoreMedia retains the owner during the call but cannot make an
escaped unsafe pointer valid after the final owner is released. Borrow APIs
never materialize payload bytes. The following operations have intentionally
distinct copy behavior:

| Operation | Payload behavior |
|---|---|
| `withContiguousStorage` | immutable scoped borrow |
| `withUnsafeMutableBytes` | mutable scoped borrow of the segment tail at the requested offset |
| range subscript / `slice(_:)` | owner plus range view |
| `fillDataBytes` | in-place mutation |
| `replaceDataBytes` | explicit source-to-storage copy |
| `copyDataBytes` | explicit storage-to-destination copy |
| `makeContiguous` on one segment | zero-copy lease reference |
| `makeContiguous` on multiple segments | one explicit payload copy |

`isContiguous` is range-specific: a slice contained by one lease range is
contiguous even when its owner has multiple segments. `withContiguousStorage`
requires the whole represented range to be nonempty and contiguous.
`withUnsafeMutableBytes(atOffset:)` instead returns only the remaining bytes in
the segment containing that offset, matching Apple's data-pointer behavior.
Neither operation hides a temporary allocation. Callers choose
`makeContiguous` when a copy is acceptable.

Cross-segment copy and replacement reject a caller buffer that overlaps any
represented lease before the first byte is changed. This prevents earlier
segment writes from corrupting bytes that a later segment has not yet read.
The caller must use disjoint storage or explicitly materialize a separate
buffer.

Append operations remain owner-isolated and non-Sendable, matching Apple's
explicit statement that append is not thread-safe. Deferred allocation and the
allocator-backed append/initializer overloads remain unimplemented.

### Sample buffer

```text
CMSampleBuffer
├── CMFormatDescription?
├── [CMSampleTimingInfo]
├── sample sizes
├── buffer-level attachments
├── per-sample attachments
└── payload
    ├── CMBlockBuffer
    ├── CVImageBuffer
    └── no payload for a stream event
```

A sample buffer may contain zero or more samples of one uniform media type. It
retains its payload lease. Timing, sizes, and format must agree with the declared
sample count.

The current image-buffer implementation accepts exactly one sample. Its public
timing input remains an array for API compatibility, but validation collapses
that input to one stored `CMSampleTimingInfo` value. This avoids persistent
per-frame timing-array storage without claiming that boundary-array creation is
allocation-free.

Readiness is an explicit state machine:

```text
unavailable ──make ready──► ready
     │                       │
     └────────failure──────► failed

any valid state ──invalidate──► invalid
```

Failed or invalid data is never exposed as an empty successful sample.

### Attachments

`CMSampleBuffer` is a `CMAttachmentBearerProtocol`. Its
`CMAttachmentBearerAttachments` storage is metadata owned by the sample buffer
and is separate from attachments on the retained Core Video image buffer. The
current portable value contract supports Boolean, signed and unsigned integer,
floating-point, string, array, and string-keyed dictionary values. Collections
are recursively typed and use Swift copy-on-write storage. It does not pretend
to accept Apple's complete `CFType` value space.

The Swift overlay supports `attachments[key]`, `propagated`,
`nonPropagated`, `merge(_:mode:)`, `removeAll()`, and
`propagateAttachments(to:)`. The C-derived operation surface also follows
Apple's basic call shapes:

- `CMGetAttachment`
- `CMCopyDictionaryOfAttachments`
- `CMSetAttachment`
- `CMSetAttachments`
- `CMRemoveAttachment`
- `CMRemoveAllAttachments`
- `CMPropagateAttachments`

Propagation first snapshots all `.shouldPropagate` entries from the source,
then updates the destination. Source and destination locks are never nested.
A timing-only sample-buffer copy retains the same image-buffer owner, creates
independent attachment storage, and copies only propagatable entries. Later
mutation of either attachment storage cannot change the other.

Per-sample attachments use separate storage from the buffer-level bearer.
`CMSampleBufferGetSampleAttachmentsArray(_:createIfNecessary:)` returns `nil`
until first materialization when requested with `false`. A `true` request or the
`sampleAttachments` property creates one fixed dictionary storage per sample and
caches it. The array view cannot change sample count; each dictionary remains
mutable through its reference-backed value view.

Apple nests `SampleAttachmentsArray` and
`PerSampleAttachmentsDictionary` under its concrete `CMSampleBuffer` type.
OpenCoreMedia's `CMSampleBuffer` is a protocol, and Swift does not permit these
nested concrete types on a protocol extension. The portable spellings are
`CMSampleAttachmentsArray` and `CMSampleAttachmentDictionary`; the property,
subscript, standard key raw values, lazy creation, and direct mutation shape
remain aligned.

`CMSampleAttachmentDictionary` is a `Sequence`. Iteration obtains one
copy-on-write dictionary snapshot so a lock is never held across caller code.
`count` and `isEmpty` read under the storage lock without exporting that
snapshot. The standard key surface contains all 13 keys exposed by the reviewed
macOS 27 Swift overlay.

Apple's array property also has a setter. The portable property is get-only:
replacing it with an array originating from a different sample count cannot
report a typed failure through a Swift property setter. Callers mutate each
fixed dictionary directly. A future whole-array replacement operation requires
an explicitly throwing contract rather than a trapping or silently truncated
setter.

A timing-only copy leaves per-sample storage unmaterialized if the source never
materialized it. Otherwise it creates independent dictionary storage from
each source dictionary directly into one destination owner array; there is no
outer snapshot array. Recursive values retain copy-on-write backing until
either copy mutates. Pixel and block payload ownership is unaffected.

The optional per-sample owner array is stored inside the sample buffer's
existing state. An unused sample therefore does not allocate a separate
attachment coordinator. Dictionary owners are created only on first requested
materialization.

## Ownership and zero-copy contract

1. `CMBlockBuffer` retains segment owners and lends scoped views.
2. `CMSampleBuffer` retains either its block buffer or image buffer.
3. Copy operations share immutable storage unless the documented operation
   explicitly requires new bytes.
4. Timing-only copies do not copy media payload.
5. Timing-only copies use independent metadata storage and propagate only
   attachments marked `.shouldPropagate`.
6. Per-sample dictionary arrays are allocated only on first requested access;
   timing copies preserve their materialized or unmaterialized state.
7. Borrowed pointers and ranges do not cross ownership or concurrency boundaries.
8. Large payloads are not converted to `Array`, `Data`, or `String` inside the
   routing path.
9. A required contiguous copy is visible in the operation and documented.

Short in-memory state is protected with `Mutex`. Ordered readiness operations that
can suspend use an actor. `await` never occurs inside `withLock`.

The fixed Swift 6.4 Embedded WASM baseline uses the same
`Synchronization.Mutex` API and internal exclusion semantics for sample
readiness, buffer-level attachments, and per-sample dictionaries as Native and
WASM; the target supplies the backend. `hasFeature(Embedded)` does not select
weaker internal exclusion for these mutable metadata paths. Public payload
`Sendable` requirements remain a separate platform contract.
ISR and DMA callback transfer remain outside these metadata objects and require
their platform-specific atomic or bounded-queue boundary.

`CMBlockBuffer` follows Apple's non-Sendable reference semantics. Its mutable
external storage is owner-isolated and is not protected by a lock; callers must
not move a buffer or borrowed pointer across concurrency boundaries.

## Platform model

The shared target depends only on the Swift standard library and OpenCoreVideo.

| Platform | Time source | Payload possibilities |
|---|---|---|
| Browser WASM | monotonic browser or host clock adapter | WASM bytes, browser-backed image buffer |
| Non-browser WASM | imported monotonic host clock | WASM bytes, host-provided image buffer |
| Embedded Swift | hardware or injected monotonic clock | static memory, DMA-backed image buffer |
| Linux/Jetson integration | monotonic system/device clock | DMA-BUF, `NvBufSurface`, V4L2, encoded bytes |
| Apple test host | reference clock and fixture storage | compared with Apple Core Media |

Clock sources are injected behind a clock contract. Platform clock APIs do not
appear in the Apple-compatible data types.

### Portable API differences

Apple's block-buffer overlay depends on `CFAllocator` and offers `Data`
materialization. The shared OpenCoreMedia target intentionally has neither
CoreFoundation nor Foundation, so allocator-taking initializers and
`dataBytes()` are absent. Platform adapters may bridge their allocator into an
external mutable buffer and deallocator closure.

Scoped borrow callbacks may throw on Native, WASM, and the fixed Swift 6.4
Embedded WASM baseline, matching Apple's Swift overlay. The borrow remains
scoped on every target; the pointer cannot escape through OpenCoreMedia-owned
storage.

Apple's `withContiguousStorage` currently creates temporary contiguous storage
for a segmented range. OpenCoreMedia intentionally returns
`nonContiguousStorage` instead, because an implicit full-payload copy would
violate the package's visible-copy rule. `makeContiguous` is the explicit
portable materialization boundary.

The macOS 27 beta implementation rejects an empty
`init(bufferReference:flags:)` even with `.permitEmptyReference`, while its
public documentation says that flag permits the operation. OpenCoreMedia follows
the documented contract and accepts the empty reference.

The macOS 27 beta overlay inconsistently reports `dataLength == 0` for a
zero-length slice but passes that zero to C APIs as a "remaining bytes"
sentinel. Consequently, its `isContiguous`, `fillDataBytes`, and
`makeContiguous` operate on the range from the slice offset to the owner end.
OpenCoreMedia preserves Swift range-value semantics instead: an interior
zero-length view is contiguous at its point, fill is a no-op, and materializing
zero bytes is a typed failure. Apple differential tests record all three
intentional differences. An actually empty owner remains noncontiguous and its
byte operations fail.

Apple range subscripts are nonthrowing and enforce valid collection indices.
OpenCoreMedia preserves those subscripts for valid basic use and additionally
offers `slice(_:) throws(CMBlockBufferError)` when the caller needs a typed range
failure instead of a precondition.

Apple attachment values may be any Core Foundation object. OpenCoreMedia has no
CoreFoundation dependency on shared targets, so `CMAttachmentValue` is a typed,
portable value set. Recursive arrays and string-keyed dictionaries are
supported. Byte payloads and platform-object boxes must gain explicit ownership
and Sendable contracts before being added; callers must not encode unsupported
values into lossy strings or ad hoc byte arrays.

## Error contract

Invalid timing, inconsistent sample counts, incompatible format descriptions,
unready data, failed data loading, invalidation, noncontiguous access, and
ownership violations are typed failures.

External block-buffer deallocation follows Apple's
`CustomBlockDeallocator` shape, whose result is `Void`. The lease invokes that
callback exactly once; there is no truthful API through which a deallocator can
report a release error after the final owner has been destroyed. Platforms that
require fallible resource shutdown must close that resource before supplying
the memory lease rather than hiding failure in deinitialization.

Apple-compatible status-code APIs translate internal typed failures at the API
boundary. No path replaces an error with `.zero`, `.invalid`, empty bytes, or an
empty sample unless Apple documents that exact result.

## Implementation sequence

1. Record the initial Apple API inventory and signature sources. **Smoke complete.**
2. Implement `CMTime` and differential tests against Apple Core Media.
   **Basic behavior complete; broad differential fixtures pending.**
3. Implement time ranges and mappings.
   **Range, mapping, clamp, and fold behavior complete.**
4. Implement media identifiers and immutable format descriptions.
   **Video Smoke complete.**
5. Implement segmented `CMBlockBuffer`.
   **Segment assembly, zero-copy references, range-aware contiguity, explicit
   materialization, and cross-segment byte operations complete. Deferred
   allocation remains pending.**
6. Implement `CMSampleTimingInfo` and ready sample buffers.
   **Image-buffer Smoke complete.**
7. Implement readiness, failure, invalidation, and attachments.
   **State, buffer-level attachments, per-sample dictionaries, and recursive
   attachment collection Smokes complete for the image-sample path. Byte values,
   platform objects, and multi-sample payload carriers remain pending.**
8. Implement clocks, timebases, and queues.
9. Add cross-platform conformance fixtures using OpenCoreVideo buffers.

Each stage requires behavior tests, native Apple comparison where available, and
WASM and Embedded builds. Declaration presence alone is never completion.
