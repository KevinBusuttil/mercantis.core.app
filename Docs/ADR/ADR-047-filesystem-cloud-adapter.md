# ADR-047 — Filesystem Reference `CloudAdapter`

**Status:** Accepted
**Date:** 2026-05-05

---

## Context

ADR-018 deliberately keeps `CloudAdapter` as a protocol seam — Core never
imports a specific cloud SDK. STATUS.md §3.5 nonetheless flagged that
shipping at least one *real* adapter would help Hub's first multi-device
customer: the only adapter in the box was `NoOpCloudAdapter`, which
acknowledges silently and returns nothing on pull.

A reference adapter has to satisfy three constraints:

1. **Genuinely peer-to-peer.** ADR-010 forbids a server component, so
   the adapter cannot assume a central queue.
2. **Available without entitlements.** CloudKit / Supabase / S3 require
   account setup. A first-customer adapter should work against a folder.
3. **Testable without cloud infrastructure.** Pointing two adapters at
   the same temp directory must simulate two devices end-to-end.

## Decision

Ship `FileSystemCloudAdapter` under `mercantis core/SyncEngine/`. It
treats a shared directory (iCloud Drive / Dropbox / OneDrive / SMB /
local-NAS) as the transport.

Layout:

```
<rootURL>/
  <deviceA>/
    .adapter-state.json    ← per-device cursor, owned by deviceA
    1.json                 ← deviceA's first pushed mutation
    2.json                 ← second
    …
  <deviceB>/
    .adapter-state.json
    1.json
    …
```

Each mutation file is a `MutationEnvelope { sourceDeviceId, peerSequence,
record: MutationRecord }` JSON. Push appends to the local device's
folder, monotonic per device. Pull walks every other folder, ingests
files with sequence > the cached peer cursor, advances both the cursor
and a synthetic `globalReceiveSequence` we hand back as
`RemoteMutation.serverSequence` so `SyncEngine.lastServerSequence`
keeps working unchanged.

State persistence: each device's `<myDir>/.adapter-state.json` carries
`localPushSequence`, `peerCursors`, and `globalReceiveSequence`. The
state file survives process restarts so a device reopening the adapter
doesn't replay every peer's history.

## Consequences

**Positive**

- A real adapter ships out of the box. Hub multi-device work is no
  longer blocked on writing one.
- Works with any consumer file-sync product (iCloud Drive / Dropbox /
  OneDrive / SMB share / local NAS). The host app picks the transport
  by choosing the `rootURL`.
- End-to-end testable in-process — the included
  `FileSystemCloudAdapterTests` simulates two devices against one
  temp directory without external services.

**Negative**

- Conflict resolution is whatever the underlying file sync provides.
  Two devices writing the same `<deviceX>/N.json` simultaneously is
  impossible (each device only writes its own subdirectory), so
  conflicts only matter for the SyncEngine's per-document conflict
  policy (ADR-006), which is unchanged.
- Cross-peer ordering is approximate. The synthetic
  `globalReceiveSequence` is monotonic on a single device but not
  globally — two devices pulling the same source files will pick
  different orderings of cross-peer interleaving. LWW resolution
  inside the engine handles this correctly; AO (append-only) DocTypes
  effectively get per-source ordering.
- File listing is O(peers × files). For very long-lived stores, peer
  directories grow unbounded; a future archival step could move
  acknowledged files to a `seen/` subdirectory.

**Neutral**

- The adapter is intentionally lock-free: each device writes only its
  own subdirectory, so no cross-process file lock is needed. The
  per-device `.adapter-state.json` is mutated only by the owning
  device's instance.
- This is a reference, not the only valid adapter. Hosts that need
  encrypted transport, server-mediated ACLs, or multi-tenant queues
  can ship their own conformer; nothing in the engine is bound to
  this implementation.
