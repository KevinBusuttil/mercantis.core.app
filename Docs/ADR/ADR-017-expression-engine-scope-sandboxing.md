# ADR-017 — Expression Engine Scope and Sandboxing

**Status:** Accepted  
**Date:** 2026-04-14

---

## Context

Frappe provides multiple expression and scripting surfaces: `safe_eval` (restricted Python), Jinja templates, Server Scripts (sandboxed Python with whitelisted modules), and Client Scripts (JavaScript). This breadth enables complex business logic but creates a large attack surface. Mercantis runs on client devices where arbitrary code execution is a security risk and violates iOS App Store rules (ADR-008).

A limited expression capability is still needed for: field visibility rules, workflow transition conditions, automation rule conditions, and formula field calculations.

## Decision

Mercantis Core's `ExpressionEngine` supports a deliberately narrow expression language:

- Field comparisons: `==`, `!=`, `>`, `<`, `>=`, `<=`
- Boolean operators: `&&`, `||`, `!`
- Arithmetic: `+`, `-`, `*`, `/`
- String interpolation in format expressions
- Parenthetical grouping
- Field references (`fieldKey` looks up the value in the evaluation context)

No loops, no function definitions, no imports, no I/O, no access to the Swift runtime.

**AST-based parsing:** The evaluator parses expressions into a typed Abstract Syntax Tree (AST) rather than using string-walking evaluation. Benefits: static analysis of field references before evaluation, constant folding for performance, and error messages that include precise source position information. The AST is the internal representation; it is not exposed to callers.

Maximum expression length and maximum nesting depth are enforced to prevent denial-of-service.

## Consequences

**Positive:**
- Provably safe — no code injection, no infinite loops, no resource exhaustion by design.
- App Store compliant — no dynamic code execution.
- AST-based parsing enables static field reference analysis and precise error messages with source positions.
- Easy to serialise and sync expressions as strings in manifest files.

**Negative:**
- Cannot express complex business logic (multi-step calculations, conditional loops, external API lookups).
- Apps that need more must decompose logic into multiple automation rules or request a Core extension.
- No user-defined functions.

**Neutral:**
- The expression syntax is a subset of common expression languages. Migration from Frappe's `safe_eval` expressions is mostly mechanical for simple conditions.
- A `lookup()` function for cross-document reads is a planned extension (not yet decided — see ARCHITECTURE-CHANGELOG.md).

---

*See also: [ADR-008 — No Arbitrary Downloaded Executable Plugins on iOS](ADR-008-no-executable-plugins-ios.md)*
