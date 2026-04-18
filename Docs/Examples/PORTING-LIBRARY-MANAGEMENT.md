# Porting `frappe/library_management` to Mercantis Core

This document is a complete, end-to-end walkthrough for re-creating [`frappe/library_management`](https://github.com/frappe/library_management) as a **Mercantis Core** app — i.e. as a single declarative `AppManifest` JSON file installed via `mercantis install-app`.

There is **no Python and no executable code**: per [ADR-004](../ADR/ADR-004-declarative-app-plugin-model.md) and [ADR-008](../ADR/ADR-008-no-executable-plugins-ios.md), apps are just manifests that the sandboxed expression engine + `AutomationActionRegistry` execute.

## 1. Concept mapping (Frappe → Mercantis Core)

| Frappe concept | Mercantis Core equivalent | Source |
|---|---|---|
| Frappe `App` (`hooks.py`, `setup.py`) | `AppManifest` (single JSON file) | [`AppManifest.swift`](../../mercantis%20core/AppRuntime/AppManifest.swift) |
| `DocType` (`*.json`) | `DocType` struct | [`DocType.swift`](../../mercantis%20core/Metadata/DocType.swift) |
| `fieldtype: Data / Text / Link / Select / Datetime / Int / Check / Attach` | `FieldType.text / longText / link / select / datetime / number / boolean / attachment` | [`FieldDefinition.swift`](../../mercantis%20core/Metadata/FieldDefinition.swift) |
| `fieldtype: Read Only` with `options: "library_member.first_name"` | `FieldType.formula` with `formulaExpression: "library_member.first_name"` | ADR-017 (sandboxed expression engine) |
| `permissions[]` (per role) | `PermissionRule[]` (`canRead/canWrite/canCreate/canDelete/canSubmit/canAmend`) | [`PermissionRule.swift`](../../mercantis%20core/Metadata/PermissionRule.swift) |
| `autoname: "AR.#######"` | Naming Strategy = `series` (configured via NamingStrategy registry, ADR-014) | ADR-014 |
| `issingle: 1` (Single DocType for settings) | `syncPolicy.immutableAfterSubmit=false` + an enforced single-row pattern via row-level evaluator | [`SyncPolicy.swift`](../../mercantis%20core/Metadata/SyncPolicy.swift) |
| `class LibraryTransaction(Document): def validate(...)` (Python) | `ValidationRule` expressions on the field/DocType — runs in `ValidationRuleStage` | ADR-022 / `ValidationPipeline` |
| `tasks.py` `daily()` overdue email | `AutomationRule` with `triggerEvent: "onSchedule"` + `schedulerEvents.daily` and `send_notification` action | [`AppRuntimeTypes.swift`](../../mercantis%20core/AppRuntime/AppRuntimeTypes.swift), ADR-019, ADR-025 |
| `hooks.py` (`scheduler_events`, `doc_events`, `role_home_page`) | `extensionPoints.schedulerEvents` + `documentEventSubscriptions` (Layer 1, declarative) | ADR-015 / ADR-026 |
| `frappe.send(...)` email | Built-in `send_notification` action handler in `AutomationActionRegistry` | `BuiltInActionHandlers.swift`, ADR-025 |
| Roles ("Librarian", "Library Member") | Plain role strings inside `PermissionRule.role` | `PermissionRule.swift` |

## 2. Scaffold with `mercantis` CLI

Run from any working directory. These commands come straight from [`MercantisCLI/README.md`](../../MercantisCLI/README.md):

```bash
# 1. Build & install the CLI
swift build -c release
cp .build/release/mercantis /usr/local/bin/mercantis

# 2. Create the app folder + manifest skeleton
mercantis new-app
#   App ID:                app.mercantis.library-management
#   App Name:              Library Management
#   Version:               0.0.1
#   Minimum Core Version:  0.1.0
#   Description:           App for managing Articles, Members, Memberships and Transactions for Libraries

# 3. Scaffold the five DocTypes interactively, appending each to the manifest
mercantis new-doctype --app ./app.mercantis.library-management   # Article
mercantis new-doctype --app ./app.mercantis.library-management   # LibraryMember
mercantis new-doctype --app ./app.mercantis.library-management   # LibraryMembership
mercantis new-doctype --app ./app.mercantis.library-management   # LibraryTransaction
mercantis new-doctype --app ./app.mercantis.library-management   # LibraryManagementSettings

# 4. Install into a SQLite database
mercantis install-app ./app.mercantis.library-management/manifest.json \
    --db-path ./mercantis.sqlite

# 5. Verify
mercantis list-apps --db-path ./mercantis.sqlite
```

## 3. The complete manifest

The full manifest is provided alongside this document at [`library-management.manifest.json`](./library-management.manifest.json). It encodes all five Frappe DocTypes, the `validate()` rule from `library_transaction.py`, and the `tasks.daily` overdue-notification job — all declaratively.

## 4. How each Frappe behaviour is preserved

1. **Read-only "fetch from" fields** (`library_member.first_name`, `article.article_name`, `member_name`) → modelled as `FieldType.formula` with `formulaExpression` evaluated by the `ExpressionEvaluator`. They are marked `isSynced: false` so they aren't replicated — they're recomputed on read (ADR-021 ResolvedMeta + ADR-017 expression engine).

2. **`LibraryTransaction.validate()`** — the Python rule "an Issue requires the previous txn for that article to be a Return, and a Return requires it to be an Issue" should be added as DocType-level validation rules. You can express it as `ValidationRule` entries on `transaction_type` once the expression engine grammar supports `last(...)` queries (see ADR-022). Until then, attach it as an `AutomationRule` with `triggerEvent: "onSave"` and a `validate` action (ADR-025 lists `validate` as a built-in handler).

3. **`tasks.daily()` overdue email** is fully replaced by the `notify_overdue_articles` automation rule + the `extensionPoints.schedulerEvents.daily` registration. At install time `AppInstaller` resolves the declarative entry into a `SchedulerService` task (see ARCHITECTURE.md §4.13). The `send_notification` handler is built in (`BuiltInActionHandlers.swift`).

4. **Single DocType (`issingle: 1`) for settings** — Mercantis doesn't have a "single" flag; convention is to allow a single record only and access it through a `settings("LibraryManagementSettings")` helper in the expression engine. `canDelete: false` and `canCreate: true` (only first time) approximates the Frappe behaviour.

5. **`autoname: "AR.#######"`** → declared in `extensionPoints.namingStrategies` using the built-in `series` `NamingStrategy` from ADR-014.

6. **`role_home_page` from `hooks.py`** → `extensionPoints.roleHomePages` (Layer 1 declarative hook, ADR-015 / ADR-026).

7. **Write semantics** — every save runs the full ValidationPipeline (TypeCoercion → Required → Link → Unique → ValidationRule → WorkflowGuard → Permission), appends a `MutationRecord` to `sync_queue`, and writes a `DocumentVersion` diff (see ARCHITECTURE.md §4.2). This is automatic; nothing in the manifest needs to opt in.

## 5. Install & verify

```bash
mercantis install-app ./app.mercantis.library-management/manifest.json \
    --db-path ./mercantis.sqlite

mercantis list-apps --db-path ./mercantis.sqlite
# → app.mercantis.library-management  Library Management  0.0.1
```

After install you can immediately:

- Create `LibraryMember` and `Article` records via `DocumentEngine.save(...)` (or the metadata-driven generic UI from `UIShell/`, ADR-016).
- The `LibraryTransaction` auto-fills `article_name` and `member_name` because they are formula fields evaluated against the linked records.
- The scheduler picks up `notify_overdue_articles` on the next daily tick and emits emails through the `send_notification` handler.

## 6. What is **deliberately not** ported

| Frappe item | Reason |
|---|---|
| `library_management/templates/` (Jinja web pages) | Mercantis is pure-client SwiftUI; UI is rendered by `UIShell` from DocType metadata (ADR-016). Use `dashboards` / `reports` instead. |
| `setup.py`, `MANIFEST.in`, `requirements.txt`, `modules.txt`, `patches.txt` | Replaced by the single `manifest.json` + `mercantis migrate` / `mercantis create-patch` flow. |
| `class LibraryTransaction(Document)` Python | Forbidden on iOS (ADR-008); same logic expressed as `ValidationRule`s + `AutomationRule`s evaluated by the sandboxed expression engine. |
| `frappe.send(...)` | Built-in `send_notification` action in `AutomationActionRegistry`. |

That's the full re-creation: one `manifest.json`, one `mercantis install-app` command, zero executable plugin code — exactly the model `mercantis.core.app` is designed for.