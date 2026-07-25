#!/bin/sh

set -eu

OPEN_CORE_MEDIA_ROOT=$(
    CDPATH= cd -- "$(dirname -- "$0")/.." && pwd
)
OPEN_CORE_MEDIA_SWIFT="${HOME}/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/swift"
OPEN_CORE_MEDIA_SDKS="${HOME}/Library/org.swift.swiftpm/swift-sdks"
OPEN_CORE_MEDIA_SDK="swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-07-17-a_wasm-embedded"
OPEN_CORE_MEDIA_TARGET_TRIPLE="wasm32-unknown-wasip1"
OPEN_CORE_MEDIA_PLATFORM_IMPLEMENTATION="embedded/Synchronization.swiftmodule/wasm32-unknown-wasip1.swiftmodule"
OPEN_CORE_MEDIA_WASM="${OPEN_CORE_MEDIA_ROOT}/.build/out/Products/Debug-webassembly-wasm32/OpenCoreMediaEmbeddedSmoke.wasm"

cd "${OPEN_CORE_MEDIA_ROOT}"

printf 'Toolchain: '
"${OPEN_CORE_MEDIA_SWIFT}" --version | sed -n '1p'
printf 'Swift SDK: %s\n' "${OPEN_CORE_MEDIA_SDK}"
printf 'Target triple: %s\n' "${OPEN_CORE_MEDIA_TARGET_TRIPLE}"
printf 'Embedded platform implementation: %s\n' \
    "${OPEN_CORE_MEDIA_PLATFORM_IMPLEMENTATION}"

perl -e 'alarm shift @ARGV; exec @ARGV' 300 \
    "${OPEN_CORE_MEDIA_SWIFT}" build \
    --swift-sdks-path "${OPEN_CORE_MEDIA_SDKS}" \
    --swift-sdk "${OPEN_CORE_MEDIA_SDK}" \
    --product OpenCoreMediaEmbeddedSmoke

perl -e 'alarm shift @ARGV; exec @ARGV' 30 \
    node --no-warnings --experimental-wasi-unstable-preview1 -e '
const fs = require("node:fs");
const { WASI } = require("node:wasi");
const path = process.argv[1];
const wasi = new WASI({ version: "preview1", args: [path], env: {} });
WebAssembly.instantiate(
    fs.readFileSync(path),
    { wasi_snapshot_preview1: wasi.wasiImport }
).then(({ instance }) => wasi.start(instance));
' "${OPEN_CORE_MEDIA_WASM}"
