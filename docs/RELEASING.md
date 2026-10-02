# Release procedure

Only release.yml publishes GitHub Releases. Branch/PR CI has read permissions.
Do not tag a migration preview as stable before PLATFORM_SUPPORT.md is verified.
Hosted CI was triggered, but GitHub refused to start the jobs because the
account is locked due to a billing issue. Resolve that account blocker before
expecting platform artifacts or tagging a release; see PLATFORM_SUPPORT.md.

1. Update Cargo.toml and the newest AppStream release to exactly the same version,
   including the prerelease suffix. Update CHANGELOG.md and platform evidence.
2. Resolve dependency advisories or document a narrow, reviewed backport.
3. Regenerate offline sources from Cargo.lock and run the native tests/UI suite.
4. Run CI on all native runners and both Flatpak architectures. Inspect its
   logs, downloaded archives, MSI installation, Mac signatures and sandbox QA.
5. After manual platform QA, create/push `v<exact Cargo version>`. The tag gate
   rejects inconsistent versions or a stale Flatpak source list. This guide
   describes publication; local packaging does not itself create a release.

Release reuses the native and Flatpak validation workflows. All jobs must pass.
The publisher merges artifacts, regenerates SHA256SUMS and calls the verifier
with `--full`, requiring exactly:

- Windows x86_64 MSI and portable zip;
- macOS Apple Silicon and Intel .app zips;
- Linux x86_64 and aarch64 native archives;
- Flatpak x86_64 and aarch64 bundles.

The verifier checks hashes, coverage, naming/version, archive safety, executable
architectures and Mac bundle metadata. Windows CI tests a synthetic older MSI,
major upgrade, shortcuts and uninstall. Flatpak CI builds/installs a test-hook
bundle, exercises it inside the sandbox, then builds a production bundle without
those hooks and verifies installation/CLI. Mac CI inspects the code signature.
Manual launch and platform UX remain necessary beyond these automated checks.

Mac bundles are ad hoc signed unless the operator configures existing Keychain
Developer ID/notary credentials. The scripts support hardened-runtime signing,
notarytool submission, stapling and repackaging. Signing secrets are not required
for local development and are never placed in the repository. The default hosted
workflow does not provision signing credentials or claim notarization.

MSI versions are numeric; see scripts/package.py for the monotonic prerelease
mapping. Public names and Cargo/AppStream preserve the full SemVer prerelease.
Never overwrite a stable release with an untested preview. Failed matrix jobs
block publication; rerun/fix them before tagging a new version.
