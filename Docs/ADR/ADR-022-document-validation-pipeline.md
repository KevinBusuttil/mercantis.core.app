# ADR-022 — Document Validation Pipeline

**Status:** Accepted  
**Date:** 2026-04-14

---

## Context

Currently, DocumentEngine performs validation inline inside `save(_:)`. Validation logic is not decomposed — type coercion, required field checks, link validation, and expression rules are interleaved in a single method. This makes individual validation stages difficult to test in isolation, and the order of validation is implicit.

As the number of validation rules grows (expressions, workflow guards, permission checks), an ad-hoc structure becomes increasingly brittle.

## Decision

Mercantis Core replaces ad-hoc inline validation with a **`ValidationPipeline`** — an ordered sequence of `ValidationStage` protocol conformances.

```swift
protocol ValidationStage {
    func validate(document: Document, meta: ResolvedMeta, context: ValidationContext) throws -> [ValidationError]
}

struct ValidationError {
    let stage: String
    let field: String?
    let message: String
}
```

Stages are executed in declared order on every `save(_:)` call:

1. **`TypeCoercionStage`** — Field values are checked against their declared `FieldType`. Mismatched types produce errors (or are coerced where safe, e.g. string `"42"` → number `42`).
2. **`RequiredFieldStage`** — Fields marked `required: true` must have a non-empty value.
3. **`LinkValidationStage`** — For fields of type `link`, the referenced document must exist in the `documents` table.
4. **`UniqueConstraintStage`** — Fields or index definitions marked `unique: true` are checked against existing documents.
5. **`ValidationRuleStage`** — `ValidationRule` expressions (declared in the DocType) are evaluated by `ExpressionEngine`. A failing rule produces a user-visible error message.
6. **`WorkflowGuardStage`** — If the document's DocType declares a `workflowId` resolvable via `ValidationContext.workflowProvider`, any change to `status` must correspond to a declared `WorkflowTransition` (`from == previous`, `to == document.status`). The transition's `allowedRoles` and `conditionExpression` are enforced. Creation and unchanged-status saves are not transitions and pass. (P1.5)
7. **`PermissionStage`** — `PermissionEngine.canPerform(operation:on:userRoles:)` (ADR-011's flat surface) is invoked to confirm the current user may perform the save operation. The operation is `.create` for brand-new documents and `.write` for updates; empty `userRoles` or an unconstrained DocType short-circuit to a pass.

If any stage produces errors, the pipeline halts and the errors are returned to the caller. The document is not persisted. All errors from a single stage are collected before halting (not just the first).

## Consequences

**Positive:**
- Each stage is independently testable.
- Validation order is explicit and consistent.
- Structured errors with stage, field, and message enable precise UI feedback.
- New validation stages can be appended without modifying existing ones.

**Negative:**
- Seven sequential stages add overhead to every save. Stages that do database lookups (link validation, unique constraints) are the most expensive.
- Stages must be carefully ordered — running permission checks before type coercion would reject saves before producing useful error messages.

**Neutral:**
- The pipeline object can be constructed with a subset of stages for testing or special contexts (e.g. import paths that skip permission checks).

---

*See also: [ADR-003 — Metadata-Defined DocTypes](ADR-003-metadata-defined-doctypes.md), [ADR-011 — Multi-Level Permission Evaluation Model](ADR-011-multi-level-permission-model.md), [ADR-013 — Submit / Cancel / Amend Document Lifecycle](ADR-013-submit-cancel-amend-lifecycle.md)*
