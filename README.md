# OpenCoreMedia

OpenCoreMedia is a pure-Swift implementation target for the Swift-visible Core
Media API on platforms where Apple's Core Media framework is unavailable.

The implemented behavior Smokes cover rational `CMTime`, `CMTimeRange`,
`CMTimeMapping`, range mapping and folding, `CMSampleTimingInfo`, immutable video
format descriptions, zero-copy image sample buffers backed by OpenCoreVideo,
buffer-level attachments with propagation modes, lazily materialized per-sample
attachment dictionaries, recursively typed attachment collections, and a
segmented zero-copy `CMBlockBuffer` owner/view path. External and deferred byte
leases can be appended or referenced without moving payload bytes. Cross-segment byte
operations traverse those leases directly, and contiguous materialization is an
explicit allocator-visible copy. Overlapping caller memory is rejected before
segmented copy or replacement begins. Every lease is released exactly once
after its last buffer or slice owner is destroyed. The current portable surface
also includes owned byte attachments, platform-value adapters, multi-sample
block buffers, revision-safe asynchronous readiness, injected clocks, anchored
timebases, and bounded timed/simple queues. Sample buffers, block buffers, and
zero-copy block slices are `Sendable` on Native, WASM, and Embedded.
Foundation `Data` materialization is isolated in
the `OpenCoreMediaFoundation` product as an explicit copy boundary.

This is not complete Core Media API compatibility. Audio/metadata format
families, timer scheduling, queue triggers, real-time lockless platform queues,
memory pools, and metadata/tag groups remain outside the completed milestone. See
[IMPLEMENTATION_PROGRESS.md](IMPLEMENTATION_PROGRESS.md) for current evidence.

## Supported production targets

- WebAssembly
- Embedded Swift

Apple-platform builds are used for compatibility and conformance testing. Apps on
Apple platforms should import Apple's `CoreMedia` framework.

## Design

Read [DESIGN.md](DESIGN.md) before adding public API or buffer implementations.
Use [APPLE_API_TRACE.md](APPLE_API_TRACE.md) to distinguish implemented,
partial, and planned Apple Core Media families.

## Build

```bash
xcodebuild test \
  -scheme OpenCoreMedia-Package \
  -destination 'platform=macOS' \
  -maximum-test-execution-time-allowance 60 \
  SWIFT_EXEC="$HOME/Library/Developer/Toolchains/swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-07-17-a.xctoolchain/usr/bin/swiftc"
"$HOME/Library/Developer/Toolchains/swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-07-17-a.xctoolchain/usr/bin/swift" build \
  --swift-sdks-path "$HOME/Library/org.swift.swiftpm/swift-sdks" \
  --swift-sdk swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-07-17-a_wasm
"$HOME/Library/Developer/Toolchains/swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-07-17-a.xctoolchain/usr/bin/swift" build \
  --swift-sdks-path "$HOME/Library/org.swift.swiftpm/swift-sdks" \
  --swift-sdk swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-07-17-a_wasm-embedded
./scripts/run-wasm-smoke.sh
./scripts/run-embedded-smoke.sh
```

The Embedded smoke links Swift's Unicode data tables in its final WASI
executable because the public attachment contract includes string keys. Library
targets compile without an application linker step; an Embedded application
using equivalent string operations must link `swiftUnicodeDataTables` in its
WASI executable target.
