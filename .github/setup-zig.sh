#!/usr/bin/env bash
set -euo pipefail

version=0.17.0
case "${RUNNER_OS}-${RUNNER_ARCH}" in
  Linux-X64) target=x86_64-linux; digest=1cbe9df9f27e6b78d14ccbca43b6703a404ef79ef1c463de901d7f088d4e2026 ;;
  Linux-ARM64) target=aarch64-linux; digest=9e8d11661d4ae3bd57702a3832781e23ad151dde5798e16a5ccd503f65234ff8 ;;
  macOS-X64) target=x86_64-macos; digest=4f9a1c5269aa17ebda5e6d3c2b89d6cbf36f7d2b22a0306e9ab98f25f95529c6 ;;
  macOS-ARM64) target=aarch64-macos; digest=b607e9b9234790a008116ae5bdb71c6243b84b9fb42a53a9e70fde41c06c536a ;;
  Windows-X64) target=x86_64-windows; digest=b5663f69581dcf391293fbf16c06cb80d81d806545ce618b4d0bab7f0eb8c428 ;;
  *) echo "Unsupported runner: ${RUNNER_OS}-${RUNNER_ARCH}" >&2; exit 1 ;;
esac
ext=tar.xz
if [[ "$RUNNER_OS" == Windows ]]; then ext=zip; fi
archive="zig-${target}-${version}.${ext}"
mkdir -p .ci-zig
curl -fsSL "https://github.com/cataggar/zig/releases/download/v${version}/${archive}" -o ".ci-zig/${archive}"
actual="$(python - ".ci-zig/${archive}" <<'PY'
import hashlib
import sys
with open(sys.argv[1], "rb") as archive:
    print(hashlib.file_digest(archive, "sha256").hexdigest())
PY
)"
[[ "$actual" == "$digest" ]] || { echo "Compiler SHA-256 mismatch" >&2; exit 1; }
if [[ "$ext" == zip ]]; then
  unzip -q ".ci-zig/${archive}" -d .ci-zig
else
  tar -xf ".ci-zig/${archive}" -C .ci-zig
fi
directory="$PWD/.ci-zig/zig-${target}-${version}"
if [[ "$RUNNER_OS" == Windows ]]; then directory="$(cygpath -w "$directory")"; fi
echo "$directory" >> "$GITHUB_PATH"
".ci-zig/zig-${target}-${version}/zig" version
