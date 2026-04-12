# ADR-008 — No Arbitrary Downloaded Executable Plugins on iOS

**Status:** Accepted  
**Date:** 2026-04-12

---

## Context

A flexible plugin architecture could allow third parties to extend Mercantis Core with arbitrary Swift code. However, Apple's App Store Review Guidelines explicitly prohibit iOS/macOS applications from downloading and executing code that was not part of the original submission. Beyond the legal/policy constraint, downloaded executable code is a significant security risk.

Two approaches to "extensibility" must be clearly distinguished:

1. **Executable plugins** — Downloadable `.dylib` files, frameworks, or scripts that are loaded and executed at runtime. **Prohibited.**
2. **Declarative manifests** — JSON/YAML files that declare schemas, workflows, and automation rules which are then interpreted by Core's own sandboxed engines. **Permitted and encouraged.**

## Decision

**Mercantis Core does not support downloadable executable plugins on any platform.**

All business logic extensibility is provided through the declarative app manifest model:
- DocTypes, fields, validation rules — defined in `AppManifest`.
- Workflows, state transitions, role guards — defined as `WorkflowDefinition` in `AppManifest`.
- Automation conditions and formula fields — expressed as strings evaluated by `ExpressionEvaluator`.
- Reports and dashboards — declared as `ReportDefinition` and `DashboardDefinition` in `AppManifest`.

`ExpressionEvaluator` evaluates expressions in a sandbox with:
- **No file system access.**
- **No network access.**
- **No access to arbitrary Swift APIs.**
- Only the current document's field values are in scope.

If JavaScriptCore or a similar runtime is used as the underlying evaluator, it MUST be configured with a restricted context — no globals, no I/O, no native bridging beyond the field value dictionary.

## Consequences

**Positive:**
- Full compliance with Apple App Store Guidelines.
- No risk of executing malicious downloaded code.
- App manifests can be inspected, audited, and version-controlled as data files.
- The declarative model is sufficient for the vast majority of business automation use cases.

**Negative:**
- Some complex business logic cannot be expressed as declarative conditions. In those cases, a Core extension (requiring a Core release) is the only path.
- The expression language must be carefully designed to balance expressiveness and safety.

**Neutral:**
- The constraint applies equally to all platforms (iOS, macOS) for consistency, even though macOS has a less restrictive runtime environment.

---

*See also: [ADR-004 — Declarative App / Plugin Model](ADR-004-declarative-app-plugin-model.md)*
