# ADR-043 — Files / Attachments Subsystem

**Status:** Accepted
**Date:** 2026-05-05

---

## Context

Every transactional ERP DocType eventually grows attachments: scanned
invoices on Sales Invoice, signed POs on Purchase Order, photos on
Stock Entry, employee CVs on Employee. STATUS.md §3.9 listed the Files
subsystem as planned but missing — `FieldType.attachment` already
existed in the metadata layer, but there was no place to actually
store the bytes.

## Decision

Three-piece subsystem under `mercantis core/Files/`:

1. **`AttachmentStore`** — filesystem byte store. Files live under
   `<rootURL>/<documentId>/<attachmentId>` so per-document deletion is
   one directory removal. SHA-256 hashing is provided as a static
   helper for content integrity / (future) dedup.
2. **`Attachment`** — typed metadata struct mirroring one row of the
   new `attachments` table.
3. **`AttachmentManager`** — public API (attach / read / list /
   delete). Holds a `MercantisDatabase` for metadata, an
   `AttachmentStore` for bytes, and an optional `AuditLogWriter` for
   compliance. Every byte write commits with the metadata row in one
   atomic write transaction; if the metadata insert fails the
   on-disk file is deleted to avoid orphans.

Migration v10 adds the `attachments` table:

```
attachments(id PK, documentId, docType, fieldKey?, fileName, mimeType,
            byteSize, storagePath, uploadedAt, uploadedBy, sha256)
```

`fieldKey` is nullable: `nil` means a general document-level
attachment, non-`nil` binds the file to a specific
`FieldType.attachment` field for typed UI rendering.

`DocumentEngine` accepts an optional `attachmentManager:` at init.
When supplied, `delete(_:)` cascades and removes every attachment
metadata row + on-disk file for the deleted document. The cascade
runs outside the document write transaction (the
`AttachmentManager` already provides its own atomic boundary), with
failures swallowed via `try?` — the document deletion is durable
and an orphan file is recoverable, while a cascade failure that
aborted the delete would leave a deleted-row-but-live-children
state that's harder to reason about.

## Consequences

**Positive**

- Hub gets a working attachments API on day one of the dependency
  bump. No bespoke per-Hub storage layer needed.
- Bytes and metadata commit atomically; integrity is verified on
  every read via SHA-256 comparison.
- The cascade-on-delete keeps the on-disk store in sync with the
  document table without bookkeeping in the caller.

**Negative**

- Attachments do not currently flow through the sync queue. Two
  devices with different attachment sets won't reconcile until a
  real `CloudAdapter` extends to attachment metadata + byte upload.
  Local-only attachments are useful immediately; multi-device
  attachment sync is a separate ADR-018 follow-up.
- Hashing every read is O(file size). For very large files this is
  measurable; a future optimisation could verify only the first /
  last N KB or move to a Merkle-style chunked hash.

**Neutral**

- Attachments are not subject to the document mutation log. The
  audit log (ADR-039) is the canonical compliance trail for attach
  / detach actions when an `AuditLogWriter` is supplied to the
  manager.
