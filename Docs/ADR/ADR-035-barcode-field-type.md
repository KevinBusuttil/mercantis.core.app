# ADR-035 — Barcode / QR Field Type

**Status:** Accepted  
**Date:** 2026-04-29

---

## Context

Stock movements, POS item lookup, and asset tagging need barcode capture.
Typing long GTINs or QR payloads manually is error-prone, but the existing field
taxonomy has no first-class barcode type or scanner UI.

## Decision

Mercantis Core adds `FieldType.barcode` as a new metadata field type.

- Persistence uses a plain `.string(...)` `FieldValue`.
- `ValidationPipeline` accepts string-backed values for barcode fields.
- `MercantisCoreUI` adds `BarcodeField`, which renders a text field plus a Scan
  button on iOS.
- Scanning uses `AVFoundation` (`AVCaptureSession` +
  `AVCaptureMetadataOutputObjectsDelegate`) inside an iOS-only
  `BarcodeScannerView`.
- On macOS the scan button is hidden and manual entry remains available.
- Consumer apps must add `NSCameraUsageDescription` to their `Info.plist`; Core
  itself does not declare camera entitlements.

## Consequences

**Positive:**

- Barcode-heavy workflows get a first-class metadata type instead of ad-hoc text
  fields.
- Existing storage and sync paths need no wire-format changes because the value
  is still a string.
- macOS keeps a no-camera fallback with the same stored representation.

**Negative:**

- Scanner integration is platform-specific and iOS-only.
- End-to-end scanner tests are not automated in this repo because
  `AVCaptureSession` requires a real camera device.

**Neutral:**

- Scanner coverage is limited to smoke tests around the field binding,
  persistence, and validation paths; the live camera path is documented as a
  known test gap.

---

*See also:
[ADR-016 — Metadata-Driven Generic UI](ADR-016-metadata-driven-generic-ui.md),
[ADR-022 — Document Validation Pipeline](ADR-022-document-validation-pipeline.md).*
