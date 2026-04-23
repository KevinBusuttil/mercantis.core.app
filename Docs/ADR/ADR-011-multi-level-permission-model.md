# ADR-011 — Multi-Level Permission Model

**Status:** Accepted (revised 2026-04-23 to match shipped code; see §P0.5 in `Docs/ENHANCEMENT-PROPOSAL.md`)
**Date:** 2026-04-14 · revised 2026-04-23

---

## Context

Frappe implements a 5+ level permission system: DocPerm (role-based CRUD per DocType with permission levels 0–9), User Permissions (record-level restrictions), sharing, field-level read/write, and workflow action guards. This system is battle-tested but complex and tightly coupled to its server-side architecture.

Mercantis Core needs an equivalent permission model that runs entirely on-device and integrates cleanly with the offline-first document lifecycle.

An earlier revision of this ADR described an **evaluator chain** (a `PermissionEvaluator` protocol, a `PermissionDecision` enum, and five concrete evaluators) modelled on the `ValidationPipeline` in ADR-022. That design remains the intended long-term direction. It has not been implemented. The shipped code is a flat `PermissionEngine` class with three direct methods, and this ADR has been rewritten so the document matches the code.

## Decision

Mercantis Core evaluates permissions through a single `PermissionEngine` class (`mercantis core/Permissions/PermissionEngine.swift`) with three public methods — one per permission scope:

```swift
public final class PermissionEngine {
    public init()

    // DocType-level: does any of the user's roles grant this operation?
    public func canPerform(
        operation: DocumentOperation,          // .read / .write / .create / .delete / .submit / .amend
        on docType: DocType,
        userRoles: Set<String>
    ) -> Bool

    // Field-level: per-field read/write gates via `FieldDefinition.permissions`.
    public func canAccessField(
        fieldKey: String,
        on docType: DocType,
        userRoles: Set<String>,
        operation: FieldOperation              // .read / .write
    ) -> Bool

    // Row-level: equality filter over a `[String: FieldValue]` dictionary.
    public func canAccessRow(
        document: Document,
        userRoles: Set<String>,
        rowFilter: [String: FieldValue]?
    ) -> Bool
}
```

### Scope-by-scope behaviour

- **DocType-level (`canPerform`)** — Iterates `docType.permissions` (`[PermissionRule]`), keeps rules whose `role` is in `userRoles`, and returns `true` on the first matching rule whose CRUD/lifecycle flag is set for the requested `DocumentOperation`. Returns `false` if no matching rule grants the operation.
- **Field-level (`canAccessField`)** — Looks up the field by key. If the field has no `permissions: FieldPermission?` block, access is granted (DocType-level already gated the operation). If it does, membership of `readRoles` or `writeRoles` — depending on `FieldOperation` — decides.
- **Row-level (`canAccessRow`)** — `rowFilter` is a `[String: FieldValue]` dictionary of required field values. Access is granted when every entry equals the document's value for the same key. A `nil` or empty `rowFilter` grants access. There is no expression support at this layer today.

### What is **not** in the shipped engine

- No `PermissionEvaluator` protocol and no `PermissionDecision` enum. The earlier revision introduced both; neither exists in code.
- No app-level / module-level check. Nothing today asks "is the user's role allowed to use this module at all?" — the engine has no opinion on it, and callers do not consult one.
- No workflow-level evaluator. Workflow transition role gates live inside `WorkflowEngine.availableTransitions`, not behind `PermissionEngine`. That remains appropriate — they consult `WorkflowTransition.allowedRoles` directly.
- No row-level expression support. `canAccessRow` compares literal `FieldValue`s; it does not evaluate a predicate via `ExpressionEvaluator`. Moving to an expression-backed row filter is tracked in `Docs/ENHANCEMENT-PROPOSAL.md` P1.7.

### Integration

- `ValidationPipeline`'s `PermissionStage` (ADR-022) calls `PermissionEngine.canPerform` before a save proceeds. Today `PermissionStage` is narrower than that — see P1.5 for its final shape — but the integration point is the flat `canPerform` method on this engine, not a chain.
- `DocumentEngine`, `WorkflowEngine`, and the UI shell all call into `PermissionEngine` directly. The method surface above is the complete public contract.

## Consequences

**Positive:**
- The public API is small, synchronous, and free of side effects — easy to call from the `ValidationPipeline`, from `WorkflowEngine`, and from the UI shell.
- Each method covers one concern (DocType / field / row), so callers pick the check they need without building a context object.
- Rules are data, not code: `DocType.permissions` and `FieldDefinition.permissions` live on the metadata, so `MetaComposer` / `ResolvedMeta` (ADR-021) already carry everything the engine needs.

**Negative:**
- App/module-level gating and workflow-level gating are not part of this engine. Callers that need those checks must go elsewhere (workflow role checks are in `WorkflowEngine`; module gating is not enforced today).
- Row-level filters are equality-only. Expression-based row filters are a P1 enhancement (`Docs/ENHANCEMENT-PROPOSAL.md` P1.7), not shipped.
- The three methods are separate entry points rather than a single `evaluate(context:)` call, so a future migration to a chain-style evaluator (see below) is an API-surface change, not a purely internal refactor.

**Neutral:**
- A chain-style design (a `PermissionEvaluator` protocol with an ordered list of concrete evaluators, short-circuiting on the first denial) is still on the table for a future ADR. It is appropriate when app-level and row-expression evaluators land and the number of concerns outgrows three hand-written methods. Until then, the flat surface matches what callers actually need.

---

*See also: [ADR-003 — Metadata-Defined DocTypes](ADR-003-metadata-defined-doctypes.md), [ADR-022 — Document Validation Pipeline](ADR-022-document-validation-pipeline.md)*
