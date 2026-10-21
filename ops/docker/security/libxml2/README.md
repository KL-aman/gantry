# libxml2 CVE-2026-6653 backport

This directory reproduces the `linux/amd64` Debian package vendored at
`vendor/libxml2-gantry1-amd64.deb`. It applies Canonical's maintained Ubuntu
Noble backport for CVE-2026-6653 to the exact Debian 13 `deb13u3` source
package. The resulting package keeps the `libxml2` package name and
`libxml2.so.2` SONAME.

The source archives, security patch, and builder image are pinned by SHA-256.
Run the builder with a new output directory:

```sh
./ops/docker/security/libxml2/build-amd64.sh /absolute/path/to/output
```

The builder:

1. downloads and verifies the exact Debian source archives;
2. applies the maintained patch and records the honest local version
   `2.12.7+dfsg+really2.9.14-2.1+deb13u3+gantry1`;
3. builds only `linux/amd64` binary packages;
4. installs the produced runtime package and runs the patched `testrecurse`
   regression against that installed shared object; and
5. compares the candidate SONAME and complete defined dynamic symbol/version
   set with the unmodified Debian `deb13u3` package.

The accepted runtime package has SHA-256
`0dfe4d8deed44dd675eb014e6a8e4c0d822ae99bb8c3a8e9dc9eeb20eb8af80e`.
See [PROVENANCE.json](PROVENANCE.json) for its source, patch, build, and
validation record.

Version-based vulnerability scanners can continue to report CVE-2026-6653
because Debian does not publish a fixed-version mapping for this custom
backport. Keep the scanner finding visible and attach the patch provenance and
focused regression result; do not add a scanner ignore.
