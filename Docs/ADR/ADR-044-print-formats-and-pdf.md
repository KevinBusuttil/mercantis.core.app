# ADR-044 — Print Formats and PDF Rendering

**Status:** Accepted
**Date:** 2026-05-05

---

## Context

Sales Invoice, Purchase Order, Delivery Note, Quotation — every
ERP-flavoured DocType eventually needs printable output. STATUS.md §3.9
listed Print / PDF as missing; the architecture had no place for either
the declarative format or the byte-producing renderer.

The decision needed to satisfy three constraints:

1. **Declarative.** Print formats live in app manifests, not code, so
   end-users / system administrators can customise without rebuilding
   the host app.
2. **Multi-format.** Plain text (CLI export, scripting) and PDF
   (customer-facing invoices) are the obvious first two; the
   architecture should not foreclose HTML / DOCX later.
3. **Cross-platform.** The same renderer code should compile on iOS,
   macOS, and (for headless tests) Linux. UI-tier dependencies belong
   in `MercantisCoreUI`, not in the engine library.

## Decision

Subsystem under `mercantis core/Printing/`:

1. **`PrintFormat`** — declarative manifest type. Carries an ordered
   list of `PrintSection` cases (heading / paragraph / fields-grid /
   child-table grid / key-value). Each section is self-describing
   structured data, not a markup string, so renderers can lay it out
   per output kind without parsing.
2. **`LetterHead`** — reusable header / footer chrome. Referenced by
   `PrintFormat.letterHeadId`.
3. **`PrintTemplate`** — shared helpers for `{field}` placeholder
   substitution and default `FieldValue → String` formatting. Every
   renderer uses these to keep behaviour consistent.
4. **`PrintRenderer`** protocol — one renderer per `PrintOutputKind`.
5. **`PlainTextPrintRenderer`** — pure-Swift, deterministic, always
   available. Doubles as the test oracle and the CLI fallback.
6. **`PDFPrintRenderer`** — Core Graphics-backed PDF renderer.
   `CoreGraphics` is available on every Apple platform and avoids
   pulling in PDFKit / SwiftUI / UIKit / AppKit. On Linux the file
   compiles to a stub that throws `backendUnavailable`.
7. **`PrintService`** — public coordinator. Holds the format / letter
   head registries and dispatches to the right renderer by output
   kind.

## Consequences

**Positive**

- Hub gets a working print path immediately for both plain text and
  PDF, declared via metadata. Sales Invoice / PO PDFs are no longer
  blocked on a UI rewrite.
- The renderer protocol cleanly separates output kind from format
  declaration; an HTML / DOCX renderer is a single new file.
- PDF rendering ships in `MercantisCore` (no UI dependency) because
  `CoreGraphics` is a low-level Apple framework, not a UI framework.

**Negative**

- The PDF renderer is text-only (mono-spaced visual style derived
  from the plain-text layout). Pixel-accurate invoice templates with
  logos, tables with vertical rules, and CSS-grade typography are
  not in scope. A future "rich" renderer could be added as a third
  `PrintRenderer` implementation behind the same protocol.
- Page break logic is naive: lines that overflow the page boundary
  push to a new page; tables don't repeat their headers on
  subsequent pages. Sufficient for a single-page invoice; revisit
  when multi-page tables become real.
- `CoreGraphics` adds an implicit Apple-platform-only contract for
  the PDF path. The `#if canImport(CoreGraphics)` guard documents
  this; downstream Linux consumers get a typed `backendUnavailable`
  error rather than a link failure.

**Neutral**

- `PrintFormat` and `LetterHead` aren't yet attached to
  `AppManifest`. Adding them is a one-line struct change once Hub
  starts shipping print formats; deferred to keep this ADR focused.
- Placeholder substitution is `{field}`-only. We deliberately avoid
  full templating syntax (loops, conditionals) to keep the surface
  manageable; complex formats should compose multiple `PrintSection`
  cases instead.
