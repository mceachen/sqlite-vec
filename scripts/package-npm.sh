#!/usr/bin/env bash

# Assemble and verify the exact npm tarball from platform build artifacts.
# Both the pre-tag rehearsal and the tag-bound publisher call this script.

set -euo pipefail

OUTPUT_DIR="${1:-package-artifact}"
EXPECTED_NAME="@photostructure/sqlite-vec"

EXPECTED_BINARIES=(
  "dist/darwin-arm64/vec0.dylib"
  "dist/darwin-x64/vec0.dylib"
  "dist/linux-arm64-musl/vec0.so"
  "dist/linux-arm64/vec0.so"
  "dist/linux-x64-musl/vec0.so"
  "dist/linux-x64/vec0.so"
  "dist/win32-arm64/vec0.dll"
  "dist/win32-x64/vec0.dll"
)

EXPECTED_PACKAGE_FILES=(
  "README.md"
  "${EXPECTED_BINARIES[@]}"
  "index.cjs"
  "index.d.ts"
  "index.mjs"
  "package.json"
)

if [[ -e "$OUTPUT_DIR" ]]; then
  echo "ERROR: Output path already exists: $OUTPUT_DIR" >&2
  exit 1
fi

mapfile -t ACTUAL_BINARIES < <(find dist -type f -print | LC_ALL=C sort)
if ! diff -u \
  <(printf '%s\n' "${EXPECTED_BINARIES[@]}") \
  <(printf '%s\n' "${ACTUAL_BINARIES[@]}"); then
  echo "ERROR: Native artifact set is incomplete or contains unexpected files" >&2
  exit 1
fi

PACKAGE_NAME="$(node -p "require('./package.json').name")"
PACKAGE_VERSION="$(node -p "require('./package.json').version")"
if [[ "$PACKAGE_NAME" != "$EXPECTED_NAME" ]]; then
  echo "ERROR: Expected package $EXPECTED_NAME, found $PACKAGE_NAME" >&2
  exit 1
fi

mkdir "$OUTPUT_DIR"
npm pack --json --ignore-scripts --pack-destination "$OUTPUT_DIR" \
  > "$OUTPUT_DIR/PACK.json"

mapfile -t TARBALLS < <(
  find "$OUTPUT_DIR" -maxdepth 1 -type f -name '*.tgz' -print
)
if [[ "${#TARBALLS[@]}" -ne 1 ]]; then
  echo "ERROR: Expected exactly one package tarball, found ${#TARBALLS[@]}" >&2
  exit 1
fi
TARBALL="${TARBALLS[0]}"

EXPECTED_NAME="$EXPECTED_NAME" \
EXPECTED_VERSION="$PACKAGE_VERSION" \
PACK_JSON="$OUTPUT_DIR/PACK.json" \
node <<'NODE'
const fs = require("node:fs");

const result = JSON.parse(fs.readFileSync(process.env.PACK_JSON, "utf8"));
if (!Array.isArray(result) || result.length !== 1) {
  throw new Error(`Expected one npm pack result, found ${result.length}`);
}
const [packed] = result;
if (
  packed.name !== process.env.EXPECTED_NAME ||
  packed.version !== process.env.EXPECTED_VERSION
) {
  throw new Error(
    `Packed ${packed.name}@${packed.version}; expected ` +
      `${process.env.EXPECTED_NAME}@${process.env.EXPECTED_VERSION}`
  );
}
NODE

TARBALL_MANIFEST="$(tar -xOf "$TARBALL" package/package.json)"
EXPECTED_NAME="$EXPECTED_NAME" \
EXPECTED_VERSION="$PACKAGE_VERSION" \
TARBALL_MANIFEST="$TARBALL_MANIFEST" \
node <<'NODE'
const manifest = JSON.parse(process.env.TARBALL_MANIFEST);
if (
  manifest.name !== process.env.EXPECTED_NAME ||
  manifest.version !== process.env.EXPECTED_VERSION
) {
  throw new Error(
    `Tarball contains ${manifest.name}@${manifest.version}; expected ` +
      `${process.env.EXPECTED_NAME}@${process.env.EXPECTED_VERSION}`
  );
}
NODE

tar -tzf "$TARBALL" |
  sed 's#^package/##' |
  LC_ALL=C sort > "$OUTPUT_DIR/CONTENTS.txt"

if ! diff -u \
  <(printf '%s\n' "${EXPECTED_PACKAGE_FILES[@]}" | LC_ALL=C sort) \
  "$OUTPUT_DIR/CONTENTS.txt"; then
  echo "ERROR: npm tarball boundary changed" >&2
  exit 1
fi

echo "Verified $PACKAGE_NAME@$PACKAGE_VERSION in $TARBALL"
