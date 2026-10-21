#!/bin/sh
set -eu
if [ "$#" -ne 1 ]; then
  echo "usage: $0 DEBIAN_LIBXML2_SOURCE_DIR" >&2
  exit 64
fi
source_dir=$1
patch_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
patch_file="$patch_dir/CVE-2026-6653.patch"
expected_patch_sha=6c2b8a7b6fa470efcb1854e5c73bd7e1ae1663d8b111e27ce9232bbc1fe44f54
if command -v sha256sum >/dev/null 2>&1; then
  actual_patch_sha=$(sha256sum "$patch_file" | awk '{print $1}')
else
  actual_patch_sha=$(shasum -a 256 "$patch_file" | awk '{print $1}')
fi
[ "$actual_patch_sha" = "$expected_patch_sha" ] || { echo "patch checksum mismatch" >&2; exit 1; }
version=$(sed -n '1{s/^[^(]*(\([^)]*\)).*$/\1/p;}' "$source_dir/debian/changelog")
[ "$version" = '2.12.7+dfsg+really2.9.14-2.1+deb13u3' ] || { echo "unexpected Debian source version: $version" >&2; exit 1; }
( cd "$source_dir" && patch -p1 --dry-run --forward < "$patch_file" )
echo "clean apply verified for $version"
