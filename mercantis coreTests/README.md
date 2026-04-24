# mercantis coreTests

XCTest coverage for Mercantis Core. Implements the P0.1 test target from
`Docs/ENHANCEMENT-PROPOSAL.md`.

## One-time Xcode setup

The `.swift` files in this directory are not yet registered with any target.
Add them by creating a Unit Testing Bundle:

1. Open `mercantis core.xcodeproj`.
2. In the Project navigator, select the project root → **+ Target**.
3. Choose **macOS** (or **iOS**, as you prefer) → **Unit Testing Bundle** →
   **Next**.
4. Name: `mercantis coreTests`. Bundle identifier: whatever matches the
   project's `PRODUCT_BUNDLE_IDENTIFIER` convention + `.tests`. Host
   application: `mercantis core`. Click **Finish**.
5. Xcode creates a default folder with a placeholder test file. **Delete
   that folder** (move to trash). You want the target to point at the
   existing `mercantis coreTests/` directory on disk.
6. Right-click the project root → **Add Files to "mercantis core"**.
   Select `mercantis coreTests/` on disk, enable **Create groups** (or
   **Add as filesystem synchronized group** in Xcode 16+), and tick only
   the `mercantis coreTests` target under "Add to targets".
7. In the test target's **Build Phases → Link Binary With Libraries**,
   add `GRDB` (same framework the app target links). The tests use
   `import GRDB` directly for a few migration and sync-queue assertions.

The main app module is exposed via `@testable import mercantis_core`.

Run the tests with `⌘U` or `xcodebuild test -scheme "mercantis core"` from
the command line.

## What's covered

| File | Subsystem | Notes |
|---|---|---|
| `ExpressionEvaluatorTests.swift` | `ExpressionEngine/` | Boolean, formula, comparisons, unary minus (P0.9 regression), division by zero, undefined field. |
| `MetaComposerTests.swift` | `Metadata/` | Custom field insertion order, property setters (`label`, `hidden`, `read_only`), cache invalidation. |
| `ConflictResolverTests.swift` | `SyncEngine/` | LWW, VCM, AO across equal/newer/stale versions. |
| `ValidationPipelineTests.swift` | `DocumentEngine/` | Each stage in isolation plus short-circuit ordering. |
| `DocumentEngineTests.swift` | `DocumentEngine/` | Save/fetch round-trip, sync-queue atomicity, `DocumentVersion` recording, optimistic concurrency, submit immutability, cancel link integrity, amend. |
| `MigrationRunnerTests.swift` | `Storage/` | v1–v6 applied in order, expected tables/columns present, idempotent re-runs, custom migrations at higher versions. |
| `NamingTests.swift` | `Naming/` | Each strategy in isolation, `NamingService` dispatch, end-to-end through `DocumentEngine.save` including the counter-gap-on-validation-failure contract. |
| `AutomationTests.swift` | `Automation/` | Each handler's happy / missing-parameter branches, registry dispatch, runner condition + re-entrancy, on-submit dispatch, scheduler-origin placeholder dispatch. |
| `ExtensionPointsTests.swift` | `AppRuntime/` | Manifest decoding, install/uninstall lifecycle, reinstall idempotency, scheduler registrar round-trip, end-to-end event dispatch, restore on launch. |
| `SchedulerTests.swift` | `Scheduling/` | Cron parser (wildcard / range / step / Sunday-as-zero-or-seven / errors), persistence round-trip + prefix-clear, due-check semantics for `.all` / `.hourly` / `.daily` / `.cron`, restart preserves cadence + fires backlog, handle-cancel preserves cadence for reinstall, `unregister(appId:)` wipes persistence, `ExtensionSchedulerRegistrar` conformance, end-to-end through `AppInstaller`. |
| `FieldValueTests.swift` | `Metadata/` | Tagged-envelope encode/decode for the P1.6 cases (`.date`, `.dateTime`, `.data`, `.array`), untagged primitive round-trip (backward-compat), recursive `.array` equality, `TypeCoercionStage` / `RequiredFieldStage` behaviour on typed dates and inline data, `ExpressionEvaluator` comparing dates as epoch seconds, `FormatStrategy` / `FieldDerivedStrategy` stringification of dates and rejection of opaque values, `FieldValueDecoder` parsing `"date"` / `"data"` parameters in `set_value`. |

Shared fixtures live in `Support/TestSupport.swift`.

## What's deliberately not covered yet

- `SyncEngine.applyRemote*` paths — P0.2 in the enhancement proposal will
  re-route these through `DocumentEngine`; tests should land with that
  change rather than lock in the current shape.
- `PermissionEngine` — P0.5 reconciles the ADR-011 chain with the flat
  implementation; testing both shapes first is wasted effort.
- `WorkflowEngine` — no persistence today (`WorkflowTransitionHistory` is
  returned but not stored). Covered once the caller contract settles.
- UI code in `UIShell/` and `Views/DesignSystem/` — UI regression tests
  are out of scope for P0.1.

## Writing new tests

Use `TestSupport` builders to stay concise:

```swift
let docType = TestSupport.makeDocType(fields: [
    TestSupport.textField("title", required: true)
])
let harness = try TestSupport.makeHarness()
defer { TestSupport.cleanUp(databaseURL: harness.url) }

try harness.registry.register(docType)
try harness.engine.save(TestSupport.makeDocument(fields: ["title": .string("hi")]))
```

Each DB-backed test uses its own tempdir and cleans up in `tearDown`. Do
not share a database across tests — GRDB `DatabasePool` keeps a persistent
WAL that can confuse parallel runs.
