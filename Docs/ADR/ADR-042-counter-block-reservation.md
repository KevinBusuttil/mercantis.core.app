# ADR-042 — Per-Device Counter Block Reservation

**Status:** Accepted
**Date:** 2026-05-05

---

## Context

`NamingSeriesStrategy` issues sequential counter values backed by a
single `naming_counters(seriesKey, value)` row per series. ADR-014
called out the open follow-up: two devices submitting Sales Invoices
offline both increment their local copy of the row from zero and pick
`SINV-2026-0001`. On sync, the VCM rejects one of the two writes — the
data is safe, but the user-facing experience is bad ("your invoice
number got changed because someone else's was the same").

ADR-014's recommended fix: each device claims a contiguous block of
counter values and issues from its block until exhausted, then claims
another. The blocks don't overlap, so collisions don't happen.

## Decision

1. **New per-device block table.** Migration v9 adds
   `naming_counter_blocks(seriesKey, deviceId, blockStart, blockEnd, nextValue)`,
   PK `(seriesKey, deviceId)`. Each row records the current block and
   the next value to issue for one device on one series.

2. **Shared allocator unchanged.** The existing `naming_counters` row
   per series remains the source of truth for "how far has this series
   advanced globally". Block reservation bumps this row by `blockSize`
   (default 50); the device's block is the resulting `[old+1, new]`
   range.

3. **`NamingCounterBlockReserver`.** Owns the reservation logic in one
   atomic write transaction:
   - If the device has a block with capacity (`nextValue <= blockEnd`),
     issue `nextValue` and increment.
   - Otherwise, advance the shared allocator by `blockSize`, derive
     the new `[blockStart, blockEnd]`, persist the device row with
     `nextValue = blockStart + 1`, and return `blockStart`.

4. **`DocumentEngine` integration.** The engine already captures its
   `deviceId` at init time. Its private `reserveCounter(...)` now
   threads `deviceId` through to the reserver; the existing
   `NamingContext.counterProvider` closure shape is unchanged.

The default `blockSize = 50` keeps single-device behaviour visually
identical to the legacy single-row path: the first device's first three
saves still produce `…0001`, `…0002`, `…0003`.

## Consequences

**Positive**

- Multi-device offline collisions on naming series are eliminated at
  the local layer. Two devices never pick the same number again.
- Single-device behaviour is preserved byte-for-byte for tests and for
  installs that never have a second device.
- The shared `naming_counters` row remains the merge target for sync;
  CRDT-style `max(local, remote)` resolution will work correctly when
  a real `CloudAdapter` ships.

**Negative**

- Counter sequences contain visible "stride" gaps after a device
  exhausts a block: device A might issue `1..50`, then `101..150` after
  device B claims `51..100`. ERPNext users tolerate this; it is
  documented in ADR-014's counter-gap note.
- Block size is a global constant today (`defaultBlockSize = 50`).
  Per-DocType tuning is a follow-up if a series with very high
  multi-device contention emerges.
- The shared `naming_counters` row still increments by `blockSize` on
  every block claim, so the visible "global counter" is no longer the
  count of issued documents. This was already approximate (counter
  gaps from validation failures); it just got coarser. Compliance
  views should rely on the audit log (ADR-039), not the global
  counter.

**Neutral**

- The reservation is done in the same `MercantisDatabase` transaction
  as the document write only when the engine wraps the call in a
  parent transaction; the default path uses a short reserver
  transaction followed by the main save transaction (matching the
  ADR-014 counter-gap behaviour).
- True cloud reconciliation (a device's block invalidates if the
  cloud has a higher value) is **not** in scope for this ADR. It
  belongs in the CloudAdapter implementation per ADR-018.
