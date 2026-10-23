#!/usr/bin/env bash
# Builds SnoopFFI.xcframework and the Swift bindings from the Rust crate.
# Requires rustup with targets aarch64-apple-ios and aarch64-apple-ios-sim.
set -euo pipefail
cd "$(dirname "$0")/../rust"

cargo build --release --target aarch64-apple-ios
cargo build --release --target aarch64-apple-ios-sim

out=../Generated
rm -rf "$out" ../SnoopFFI.xcframework
mkdir -p "$out/headers"

cargo run --release --bin uniffi-bindgen -- generate \
  --library target/aarch64-apple-ios/release/libsnoop_ios_ffi.a \
  --language swift --out-dir "$out"
mv "$out"/*.h "$out/headers/"
mv "$out"/*.modulemap "$out/headers/module.modulemap"

xcodebuild -create-xcframework \
  -library target/aarch64-apple-ios/release/libsnoop_ios_ffi.a -headers "$out/headers" \
  -library target/aarch64-apple-ios-sim/release/libsnoop_ios_ffi.a -headers "$out/headers" \
  -output ../SnoopFFI.xcframework

echo "built SnoopFFI.xcframework and $out/*.swift"
