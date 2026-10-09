# Fork automation

This fork builds Madeira from source with the twelve unmodified Microsoft
Visual C++ x64 runtime DLLs described in `tools/fetch-vcruntime.md`.

## Workflows

- **Sync upstream** (`sync-upstream.yml`): runs daily at 02:17 UTC and can be
  started manually. Merges `willfaust/Madeira/main` into this fork's `main`,
  preserves local commits, and dispatches an IPA build when the merge changes
  the branch. A merge conflict fails the run without pushing or force-resetting
  the fork. Resolve the conflict manually and rerun.
- **Build and release IPA** (`build-ipa.yml`): runs on code pushes to `main`
  or manually. The optional `commit` input selects the exact source revision.
  Builds on an ARM64 macOS runner with Xcode 26, uses **Debug** as required by
  the upstream build record, validates the payload, uploads an Actions artifact
  and publishes a GitHub release with a unique `build-<run>-<attempt>` tag.

The workflows use the repository's `GITHUB_TOKEN`; no signing certificate,
Apple account or personal access token is needed. Actions must be enabled on
the fork. The sync job explicitly dispatches the build because a push made
with `GITHUB_TOKEN` does not trigger another push workflow.

## Inputs and verification

`tools/ci-prepare.sh` fetches the llvm-mingw toolchain and LLVM revision from
`docs/BUILDING.md`, plus FreeType 2.13.3. Submodules are checked out at the
repository's recorded commits, never the latest tip of their branches.
`tools/ci-build.sh` builds native libraries, the Windows modules, Madeira Dock,
WoW64 and the app. Only the expensive pinned LLVM/toolchain build is cached;
Wine, FEX, DXMT and the application rebuild from the selected sources.

`tools/fetch-vcruntime.py` downloads Microsoft's Visual C++ 2022 x64 installer
14.44.35211.0 from its fixed Microsoft URL and verifies its SHA-256. It extracts
the nested WiX CAB payloads with 7-Zip, selects x64 PE files, checks that their
Authenticode certificate payloads are intact, and records DLL hashes. It never
strips or modifies DLLs. The binaries and generated manifest stay gitignored.
See Microsoft's redistribution terms in `tools/fetch-vcruntime.md`.

`tools/verify-ipa.py` checks the zipped IPA for corruption, the ARM64 app,
JIT extension, StikJIT framework, converter, Dock, WoW64 and all twelve runtime
DLLs. Packaged DLLs must match their extraction hashes byte-for-byte and still
contain their certificate payloads. This checks packaging, not certificate
trust or device gameplay. Releases include `SHA256SUMS`, `build-info.txt`
(source/submodule revisions and Xcode version) and `vcruntime-manifest.json`.

## Installing and testing

Download `Madeira-vcruntime.ipa` from this fork's Releases and sign/sideload
with your own Apple ID. The CI IPA is unsigned. iOS 26+, JIT and Memory+ are
required; follow `docs/JIT.md`. Wine Mono follows upstream release behavior:
the app downloads it on demand rather than shipping it inside the IPA.

A successful build establishes that the code compiles and the package contains
the verified runtime. Actual game launch and JIT behavior must be tested on an
iPhone; a hosted Actions runner cannot validate those device-only features.
