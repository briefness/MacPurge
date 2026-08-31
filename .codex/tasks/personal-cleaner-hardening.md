Goal: Harden the personal macOS cleaner without adding commercial licensing or network features.

Completed:
- Cleanup rejects dangerous roots, system prefixes, symbolic links, changed file identities, and protected-path overlap immediately before moving files.
- Custom folders are search roots, never cleanup targets themselves.
- Missing, changed, duplicate, and partial-failure paths are reported; nested selected paths no longer double-count processed bytes.
- Directories truncated at 200,000 entries are visibly marked, excluded from all selection flows, and rejected again by the cleanup service.
- Swift tests cover path policy and incomplete-result selection behavior.
- Permission scopes match implemented features; mail/message and Trash claims were removed.
- Misleading memory purge optimization was removed.
- Packaging supports ad-hoc signing and an optional fixed local code-signing identity.
- The monolithic Swift source was split into app state/services, models, views, and cleanup safety policy.
- README now states the app is personal-use and that rust-core is not connected to the Swift application.
- Added CLI-aligned trash, storage analyzer, settings, age-based artifact recommendations, Docker/mise/Xcode rules, and optional CLI-backed RAM/purgeable maintenance.
- Renamed the visible product to “清爽 Mac”, added a generated native macOS AppIcon.icns, and updated Bundle metadata and packaging.
- Hardened protected-path containment for `/`, blocked other users' home directories, rejected glob metacharacters in custom roots, and fail closed when file identity cannot be revalidated.
- Added bounded, cancellable background scans; removed automatic recursive startup storage scans; stopped recursive traversal at volume boundaries.
- Made Trash default to no selection, moved permanent deletion off the main thread, and serialized filesystem and optimization operations.
- Recommendation selection now requires both a safe review level and the configured artifact age.
- Added an independent Application Uninstall module: real scans of `/Applications` and `~/Applications`, Bundle ID-based residual discovery, per-path risk/evidence display, running-app protection, resource identity revalidation, recoverable Trash moves, and uninstall reports.
- System apps, symbolic links, shared/uncertain paths, incomplete reads, and unreadable identities fail closed; recommended uninstall selection only includes the app bundle and rebuildable caches.

Preserved invariants:
- Native SwiftUI/AppKit desktop application.
- Only real local scan data is displayed.
- Cleanup moves recoverable items to Trash rather than permanently deleting them.
- Existing four-level cleanup hierarchy and Chinese UI remain.

Validation completed 2026-08-31:
- `swift test`: 21 tests passed, including uninstall path safety coverage.
- `swift build -c release`: passed.
- `cargo test`: passed, but rust-core currently contains no Rust tests and is not linked.
- `./scripts/package-app.sh`: generated 清爽 Mac.app.
- `codesign --verify --deep --strict --verbose=2 清爽 Mac.app`: passed with ad-hoc arm64 signature.
- Static scan found no mock/demo/TODO/commercial-payment markers.

Remaining risk:
- Automated visual inspection could not run because Codex lacks macOS Accessibility and Screen Recording permissions. No GUI interaction or cleanup was performed during validation.
