#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: $0 OUTPUT_DIR" >&2
  exit 64
fi

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
out_parent=$(CDPATH= cd -- "$(dirname -- "$1")" && pwd)
out="$out_parent/$(basename -- "$1")"
image='debian:trixie-slim@sha256:62bd423aeee912639ca8ee681c2b762cb3e25137e0a92b20be455898a9f034ad'

[ ! -e "$out" ] || { echo "refusing to overwrite $out" >&2; exit 1; }
mkdir -p "$out"

docker run --rm --platform linux/amd64 \
  -e DEBIAN_FRONTEND=noninteractive \
  -e SOURCE_DATE_EPOCH=1782210600 \
  -v "$script_dir:/security:ro" \
  -v "$out:/out" \
  "$image" sh -ec '
cat >/etc/apt/sources.list.d/debian-src.sources <<"EOF"
Types: deb-src
URIs: http://deb.debian.org/debian
Suites: trixie trixie-updates
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.pgp

Types: deb-src
URIs: http://deb.debian.org/debian-security
Suites: trixie-security
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.pgp
EOF
apt-get update
apt-get install -y --no-install-recommends \
  binutils ca-certificates curl devscripts dpkg-dev equivs
apt-get build-dep -y -P nopython \
  libxml2=2.12.7+dfsg+really2.9.14-2.1+deb13u3

mkdir -p /build/input
cd /build/input
base_url=https://deb.debian.org/debian/pool/main/libx/libxml2
curl -fsSLO "$base_url/libxml2_2.12.7+dfsg+really2.9.14-2.1+deb13u3.dsc"
curl -fsSLO "$base_url/libxml2_2.12.7+dfsg+really2.9.14.orig.tar.xz"
curl -fsSLO "$base_url/libxml2_2.12.7+dfsg+really2.9.14-2.1+deb13u3.debian.tar.xz"
sha256sum -c <<"EOF"
04b1da890535b11e3db231f39114ee09e643badceff79441d749d0ca78efaaa5  libxml2_2.12.7+dfsg+really2.9.14-2.1+deb13u3.dsc
4fe913dec8b1ab89d13b489b419a8203176ea39e931eaa0d25b17eafb9c279e9  libxml2_2.12.7+dfsg+really2.9.14.orig.tar.xz
3b6d265f482d6a8fbe3c056d2006fb3b563b4a838f7258b388ac5f0b29206921  libxml2_2.12.7+dfsg+really2.9.14-2.1+deb13u3.debian.tar.xz
6c2b8a7b6fa470efcb1854e5c73bd7e1ae1663d8b111e27ce9232bbc1fe44f54  /security/CVE-2026-6653.patch
EOF

cd /build
dpkg-source -x \
  input/libxml2_2.12.7+dfsg+really2.9.14-2.1+deb13u3.dsc src
cp /security/CVE-2026-6653.patch src/debian/patches/CVE-2026-6653.patch
printf "%s\n" CVE-2026-6653.patch >> src/debian/patches/series
cat >/tmp/changelog.entry <<"EOF"
libxml2 (2.12.7+dfsg+really2.9.14-2.1+deb13u3+gantry1) trixie; urgency=high

  * Backport Canonical Ubuntu Noble security fix for CVE-2026-6653,
    derived from upstream commit 463bbeeca1805b5c4828f50d0fefc4eebaf620df.

 -- Gantry Security Build <security@localhost>  Wed, 21 Oct 2026 18:40:00 +0530

EOF
cat src/debian/changelog >> /tmp/changelog.entry
cat /tmp/changelog.entry > src/debian/changelog

cd src
DEB_BUILD_OPTIONS="nocheck reproducible=+fixfilepath" DEB_BUILD_PROFILES=nopython \
  dpkg-buildpackage -B -us -uc -P nopython
cd ..
candidate_deb=$(find . -maxdepth 1 \
  -name "libxml2_*+gantry1_amd64.deb" -print -quit)
[ -n "$candidate_deb" ]
cp ./*+gantry1_amd64.deb /out/
cp /security/CVE-2026-6653.patch /out/

# Reapply the quilt stack after dpkg-buildpackage calls dpkg-source
# --after-build. Compile the patched regression directly against the shared
# object installed from the produced runtime package.
cd src
dpkg-source --before-build .
dpkg -i "/build/$candidate_deb" > /out/installed-dpkg.log 2>&1
gcc -DHAVE_CONFIG_H \
  -Ibuilddir/main -Ibuilddir/main/include -Iinclude \
  -o /tmp/testrecurse-installed testrecurse.c \
  /usr/lib/x86_64-linux-gnu/libxml2.so.2.9.14 \
  -lpthread -lz -llzma -lm
ldd /tmp/testrecurse-installed > /out/testrecurse-installed-ldd.txt
readlink -f /usr/lib/x86_64-linux-gnu/libxml2.so.2 \
  >> /out/testrecurse-installed-ldd.txt
/tmp/testrecurse-installed > /out/testrecurse-installed.log 2>&1
dpkg-query -W libxml2 > /out/installed-control.txt
sha256sum "/build/$candidate_deb" \
  /usr/lib/x86_64-linux-gnu/libxml2.so.2.9.14 \
  > /out/installed-library-sha256.txt

cd /build
apt-get download \
  libxml2=2.12.7+dfsg+really2.9.14-2.1+deb13u3
base_deb=$(find . -maxdepth 1 \
  -name "libxml2_2.12.7+dfsg+really2.9.14-2.1+deb13u3_amd64.deb" \
  -print -quit)
[ -n "$base_deb" ]
mkdir -p /compare/base /compare/candidate
dpkg-deb -x "$base_deb" /compare/base
dpkg-deb -x "$candidate_deb" /compare/candidate
base_so=$(find /compare/base -name "libxml2.so.2.*" -type f -print -quit)
candidate_so=$(find /compare/candidate -name "libxml2.so.2.*" \
  -type f -print -quit)
readelf -d "$base_so" | grep SONAME > /out/base-soname.txt
readelf -d "$candidate_so" | grep SONAME > /out/candidate-soname.txt
diff -u /out/base-soname.txt /out/candidate-soname.txt > /out/soname.diff
nm -D --defined-only --with-symbol-versions "$base_so" \
  | awk "{print \$2, \$3}" | sort -u \
  > /out/base-exported-symbols.txt
nm -D --defined-only --with-symbol-versions "$candidate_so" \
  | awk "{print \$2, \$3}" | sort -u \
  > /out/candidate-exported-symbols.txt
diff -u /out/base-exported-symbols.txt \
  /out/candidate-exported-symbols.txt > /out/exported-symbols.diff
dpkg-deb -f "$base_deb" Package Version Architecture Depends \
  > /out/base-control.txt
dpkg-deb -f "$candidate_deb" Package Version Architecture Depends \
  > /out/candidate-control.txt
dpkg-deb --info "$candidate_deb" > /out/candidate-deb-info.txt
dpkg-deb --contents "$candidate_deb" > /out/candidate-deb-contents.txt
cp "$base_deb" /out/
cp src/debian/changelog /out/candidate-changelog
sha256sum /out/*.deb /out/CVE-2026-6653.patch > /out/SHA256SUMS
'
