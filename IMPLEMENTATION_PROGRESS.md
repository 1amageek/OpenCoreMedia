# OpenCoreMedia Implementation Progress

## Apple API trace

- [x] Framework header-family inventory recorded in `APPLE_API_TRACE.md`
- [x] Implemented, partial, and planned responsibilities are distinguished
- [x] Callable partial `CMBlockBuffer` behavior has a source marker
- [x] Callable partial attachment-value behavior has a source marker
- [x] Missing `CMBlockBuffer` attachment-bearer path has a source marker

## Smoke definition

The first smoke milestone is complete only when behavior tests demonstrate:

- valid, invalid, indefinite, and infinite `CMTime` values;
- checked `CMTime` arithmetic, scale conversion, and comparison;
- `CMSampleTimingInfo` value semantics;
- an immutable video format description;
- a ready `CMSampleBuffer` retaining an OpenCoreVideo image buffer without
  copying its storage;
- typed failures for inconsistent timing, format, and sample counts;
- typed failures for unready and invalidated payload access;
- successful native tests and sequential WASM and Embedded WASM builds.

The second Smoke additionally requires:

- Apple-compatible `CMTimeRange` construction, predicates, half-open
  containment, intersection, and union;
- a `CMBlockBuffer` retaining externally supplied storage without copying;
- `init(referencing:)` and `CMBlockBuffer.Slice` sharing that same memory lease;
- scoped immutable and mutable byte borrows preserving the source address;
- typed range and storage-policy failures;
- explicit copy naming and bounds for copy and replace operations;
- exactly-once external release after the final buffer or slice owner dies.

The buffer-level attachment slice additionally requires:

- Apple-shaped Swift overlay and get, copy, set, remove, and propagate
  operations;
- a mode stored with every value and replacement across modes;
- propagation of only `.shouldPropagate` values;
- independent attachment storage in a timing-only copy;
- unchanged zero-copy image payload ownership;
- differential behavior against Apple Core Media.

The per-sample attachment slice additionally requires:

- no attachment dictionary allocation before first requested access;
- one fixed dictionary view per declared sample;
- direct mutation through Apple-shaped array and key subscripts;
- all 13 standard sample key raw values from the reviewed SDK overlay;
- direct dictionary iteration through `Sequence`;
- typed failure for incompatible standard-key value access;
- recursive array and string-keyed dictionary values;
- independent metadata after a timing-only copy;
- unchanged zero-copy image payload ownership;
- differential behavior against Apple Core Media.

## Required implementation

### Time

- [x] `CMTimeValue`, `CMTimeScale`, and `CMTimeEpoch`
- [x] `CMTimeFlags`
- [x] `CMTimeRoundingMethod`
- [x] `CMTime` special values and predicates
- [x] Checked arithmetic and scale conversion
- [x] Exact comparison without floating-point conversion
- [x] `CMTimeRange` start/duration and start/end construction
- [x] `CMTimeRange` validity, empty, indefinite, and end predicates
- [x] Half-open time and range containment
- [x] Intersection and union
- [x] `CMTimeMapping` value and factory semantics
- [x] Linear time and duration mapping
- [x] Range clamping
- [x] Exact positive and negative range folding
- [x] Apple differential mapping and folding fixtures
- [ ] Apple differential fixtures for broader overflow and epoch combinations

### Timing and formats

- [x] `CMSampleTimingInfo`
- [x] Media type and subtype identifiers
- [x] Immutable video format description
- [x] Format-to-image-buffer compatibility validation

### Sample buffers

- [x] Typed sample-buffer errors
- [x] Ready image sample construction
- [x] Zero-copy image-buffer retention
- [x] Readiness and invalidation state transitions
- [x] Timing, format, and count validation
- [x] Scalar timing storage for the single-image sample path
- [x] `CMAttachmentBearerProtocol` and `CMAttachmentBearerAttachments`
- [x] Keyed Swift-overlay access, merge, remove-all, and propagation
- [x] Attachment modes and scalar portable values
- [x] Recursive attachment array and dictionary values
- [x] Get, copy, set, batch set, remove, and remove-all operations
- [x] Propagatable-only attachment transfer
- [x] Timing-copy attachment propagation into independent storage
- [x] Lazy fixed-length per-sample attachment array
- [x] Mutable, iterable per-sample dictionary views and all standard keys
- [x] Typed Boolean access and incompatible-value failure
- [x] Timing-copy preservation and independent per-sample metadata
- [ ] Attachment byte values and platform-object adapters
- [ ] Multi-sample payload carrier

### Block buffers

- [x] `CMBlockBufferProtocol` owner and index contract
- [x] External contiguous buffer construction
- [x] Zero-copy `init(referencing:)`
- [x] `CMBlockBuffer.Slice` retaining owner plus range
- [x] Range, closed-range, partial-range, and unbounded subscripts
- [x] Typed `slice(_:)` validation
- [x] Scoped immutable and mutable borrows
- [x] Explicit `copyDataBytes`, `replaceDataBytes`, and `fillDataBytes`
- [x] Exactly-once external deallocation
- [ ] Multiple memory segments and append
- [ ] Explicit contiguous materialization
- [ ] Deferred allocation

## Copy boundary

`CMImageSampleBuffer` retains the supplied generic `CVPixelBuffer` reference.
It does not read, copy, convert, or materialize payload bytes. A timing-only
copy retains that same image-buffer reference and allocates only timing metadata,
its own small readiness state, and independent attachment storage. Only
`.shouldPropagate` metadata is inserted into the copy. The native Smoke verifies
object identity and shared mutation through borrowed pixel-buffer byte access:
writes through the source, original sample, and timing-only copy are observed
from the same media storage, while later attachment mutations remain isolated.

Per-sample attachment storage starts unmaterialized. First requested access
creates a fixed array with one dictionary owner per sample. A timing copy
preserves the unmaterialized state when the source has no per-sample metadata.
When materialized, it copies each dictionary directly into one destination
owner array. Recursive array and dictionary values use copy-on-write backing;
no image bytes are read or copied. The optional owner array lives in the
sample's existing state, so unused per-sample attachments do not require a
separate coordinator allocation.

The public initializer retains its one-element timing-array input for API
compatibility. After validating that input, the single-sample implementation
stores one `CMSampleTimingInfo` value rather than retaining an `Array` inside
every sample object. This removes persistent array storage from the high-rate
sample path, but does not claim that construction is allocation-free because
the caller still creates the boundary array.

The concrete sample buffer is generic over its pixel buffer and video format.
This avoids existential dispatch on Embedded Swift while preserving protocol
abstraction. Native, WASM, and the fixed Swift 6.4 Embedded WASM baseline use
the same Mutex API and exclusion semantics. Lock ownership is separated:
`CMImageSampleBuffer.State` protects validity, readiness, and the optional
per-sample storage array; `CMAttachmentStorageReference` protects buffer-level
attachments; each `CMSampleAttachmentDictionaryStorage` protects one
per-sample dictionary. The target runtime supplies the Mutex implementation;
no locks are nested, and no `await` or media-byte work occurs while a lock is
held.

`CMBlockBuffer` stores an external-memory lease rather than payload bytes.
References share the lease and slices retain an owner plus range. Borrow
closures receive the original pointer, adjusted only by their range offset.
Only `copyDataBytes` and `replaceDataBytes` copy payload bytes, and both expose
their required bounds in typed failures. `fillDataBytes` mutates in place.

## Apple API review evidence

Reviewed with `remark` on 2026-07-24:

- `CMTime`
- `CMTimeFlags`
- `CMTimeRoundingMethod`
- `CMTime.+`
- `CMTime.-`
- `CMTime.convertScale`
- `CMTimeCompare`
- `CMSampleTimingInfo`
- `CMFormatDescription`
- `CMVideoFormatDescription`
- `CMSampleBuffer`
- `CMSampleBuffer.imageBuffer`
- `CMSampleBuffer.formatDescription`
- `CMSampleBuffer.numSamples`
- `CMSampleBuffer.invalidate`
- `CMTimeRange`
- `CMTimeRange.init(start:duration:)`
- `CMTimeRange.init(start:end:)`
- `CMTimeRange.containsTime`
- `CMTimeRange.containsTimeRange`
- `CMTimeRange.intersection`
- `CMTimeRange.union`
- `CMTimeMapping`
- `CMTimeMapping.init(source:target:)`
- `CMTimeMapping.invalid`
- `CMTimeMappingMake`
- `CMTimeMappingMakeEmpty`
- `CMTimeMapTimeFromRangeToRange`
- `CMTimeMapDurationFromRangeToRange`
- `CMTimeClampToRange`
- `CMTimeFoldIntoRange`
- `CMBlockBuffer`
- `CMBlockBuffer.init(buffer:deallocator:flags:)`
- `CMBlockBuffer.init(referencing:)`
- `CMBlockBufferProtocol`
- `CMBlockBuffer.Slice`
- `CMBlockBuffer.withUnsafeMutableBytes`
- `CMBlockBufferProtocol.withContiguousStorage`
- `CMBlockBufferProtocol.copyDataBytes`
- `CMBlockBufferProtocol.replaceDataBytes`
- `CMBlockBufferProtocol.fillDataBytes`
- `CMAttachment`
- `CMAttachmentBearerProtocol`
- `CMAttachmentBearerAttachments`
- `CMGetAttachment`
- `CMCopyDictionaryOfAttachments`
- `CMSetAttachment`
- `CMSetAttachments`
- `CMRemoveAttachment`
- `CMRemoveAllAttachments`
- `CMPropagateAttachments`
- `CMSampleBufferGetSampleAttachmentsArray`
- `CMSampleBuffer.sampleAttachments`
- `CMSampleBuffer.SampleAttachmentsArray`
- `CMSampleBuffer.PerSampleAttachmentsDictionary`
- `CMSampleBuffer.PerSampleAttachmentsDictionary.Key`
- Sample Attachment Keys
- `CMSampleBufferCreateCopy`
- `CMSampleBufferCreateCopyWithNewTiming`

The second Smoke checked the Swift declarations emitted from the local macOS 27
SDK with `swift-symbolgraph-extract` and read `CMTimeRange.h` and
`CMBlockBuffer.h` directly. The per-sample attachment slice refreshed that
symbol graph on 2026-07-25 and read the relevant `CMSampleBuffer.h` declarations.
The reviewed behavior and portable differences are recorded in `DESIGN.md`.
Additional Apple-named APIs must be reviewed and added to this list before
implementation.

## Test evidence

- Native:
  `xcodebuild test -scheme OpenCoreMedia-Package -destination 'platform=macOS'
  -maximum-test-execution-time-allowance 30
  -only-testing:OpenCoreMediaTests
  SWIFT_EXEC=~/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/swiftc`
  — passed 43 behavior tests in 9 suites with the Swift 6.4 development
  snapshot compiler on 2026-07-25.
- Time mapping differential:
  `xcodebuild test -scheme OpenCoreMedia-Package -destination 'platform=macOS'
  -maximum-test-execution-time-allowance 30
  -only-testing:OpenCoreMediaTests/CMTimeMappingSmokeTests
  -only-testing:OpenCoreMediaTests/CMTimeMappingAppleDifferentialTests`
  — passed on 2026-07-24, including raw versus validating construction,
  endpoint preservation, nonintegral nanosecond mapping, epoch failures,
  infinite ranges, clamping, and positive/negative folding.
- Scalar timing-storage regression:
  `xcodebuild test -scheme OpenCoreMedia-Package -destination 'platform=macOS'
  -maximum-test-execution-time-allowance 30
  -only-testing:OpenCoreMediaTests/SampleBufferSmokeTests`
  — passed on 2026-07-24, including index `0`, negative, and upper-bound
  timing access plus payload identity and readiness behavior.
- Buffer-level attachments:
  `xcodebuild test -scheme OpenCoreMedia-Package -destination 'platform=macOS'
  -maximum-test-execution-time-allowance 30
  -only-testing:OpenCoreMediaTests/CMAttachmentSmokeTests
  -only-testing:OpenCoreMediaTests/CMAttachmentAppleDifferentialTests
  -only-testing:OpenCoreMediaTests/SampleBufferSmokeTests`
  — passed 11 tests on 2026-07-24, including Apple timing-copy propagation,
  independent metadata storage, and unchanged image-buffer identity.
- Per-sample attachments:
  `xcodebuild test -scheme OpenCoreMedia-Package -destination 'platform=macOS'
  -maximum-test-execution-time-allowance 30
  -only-testing:OpenCoreMediaTests/CMSampleAttachmentSmokeTests
  -only-testing:OpenCoreMediaTests/CMAttachmentAppleDifferentialTests
  SWIFT_EXEC=~/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/swiftc`
  — passed on 2026-07-25, including lazy creation, fixed length, direct
  mutation, all standard raw keys, direct iteration, typed mismatch failure,
  recursive values, concurrent mutation/copy, Apple copy behavior, independent
  metadata, and unchanged image-buffer identity.
- WASM:
  `~/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/swift build
  --swift-sdks-path ~/Library/org.swift.swiftpm/swift-sdks
  --swift-sdk
  swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-07-17-a_wasm
  --target OpenCoreMedia`
  — passed after `swift package clean` with the matching Swift 6.4
  development snapshot compiler and SDK on 2026-07-25.
- Embedded WASM:
  `~/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/swift build
  --swift-sdks-path ~/Library/org.swift.swiftpm/swift-sdks
  --swift-sdk
  swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-07-17-a_wasm-embedded
  --target OpenCoreMedia`
  — passed after `swift package clean` with the matching Swift 6.4
  development snapshot compiler and SDK on 2026-07-25. The target triple is
  `wasm32-unknown-wasip1`; the Embedded platform module is
  `embedded/Synchronization.swiftmodule/wasm32-unknown-wasip1.swiftmodule`.
- Embedded runtime:
  `./scripts/run-embedded-smoke.sh`
  — built `OpenCoreMediaEmbeddedSmoke.wasm` with the fixed Swift 6.4
  Embedded SDK and executed it through Node WASI on 2026-07-25. The smoke
  validates Mutex-protected not-ready and typed-failure recovery, buffer-level
  propagation, lazy per-sample creation, recursive mutation, throwing scoped
  borrows, timing-copy metadata independence, and unchanged image-buffer
  identity. The script records the toolchain, Swift SDK, target triple, and
  Embedded Synchronization module identifiers. Node WASI is a single-threaded
  execution fixture; Native concurrent state, buffer-level attachment, and
  per-sample mutation/copy tests provide the current contention test.
- Native Thread Sanitizer:
  `xcodebuild test -quiet -scheme OpenCoreMedia-Package
  -destination 'platform=macOS'
  -only-testing:OpenCoreMediaTests/CMAttachmentSmokeTests
  -only-testing:OpenCoreMediaTests/CMSampleAttachmentSmokeTests
  -enableThreadSanitizer YES
  SWIFT_EXEC=~/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/swiftc`
  — passed on 2026-07-25, exercising concurrent readiness, lazy
  materialization, buffer-level snapshot/propagation, and per-sample
  mutation/copy paths under Thread Sanitizer.

## Explicitly not implemented

- segmented or deferred-allocation `CMBlockBuffer`
- `CMBlockBuffer.append`, `makeContiguous`, and Foundation `dataBytes`
- attachment byte values and arbitrary platform-object values
- multi-sample payload carriers
- asynchronous data readiness callbacks
- clocks, timebases, and queues
- platform camera, codec, and file adapters
