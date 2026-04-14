# ADR-010 — Pure Client-Side Architecture (No Server Component)

**Status:** Accepted  
**Date:** 2026-04-14

---

## Context

Frappe is a full server-side web framework (Python, WSGI, MariaDB, Redis, RQ workers). It requires a server process for every operation. Mercantis targets iOS/macOS as a native application that must work fully offline.

Running a server process on a mobile or desktop device is impractical: it requires background daemon management, conflicts with App Store sandbox rules, consumes battery, and creates infrastructure that users cannot reasonably operate.

## Decision

Mercantis Core is a pure Swift client-side library. There is no server process, no web framework, no background daemon. All logic executes within the app process. The Cloud Adapter is a protocol boundary — Core defines the interface; the host application or a separate service provides the cloud implementation.

## Consequences

**Positive:**
- True offline-first: the app is fully functional with no network connection.
- Zero server infrastructure required for single-user use.
- App Store compliant — no background daemons or out-of-process code execution.
- All operations are instant (local SQLite, no network round-trip).

**Negative:**
- No server-side hooks or middleware.
- No multi-user real-time collaboration without a cloud backend.
- Background processing is limited to the app process lifetime.
- No server-side security enforcement — all security checks are client-side only.

**Neutral:**
- The Cloud Adapter protocol allows future server-side implementations (REST API, Firebase, Supabase) without changing Core.

---

*See also: [ADR-002 — SQLite as Local Source of Truth](ADR-002-sqlite-local-source-of-truth.md), [ADR-018 — Cloud Adapter as Protocol Boundary](ADR-018-cloud-adapter-protocol-boundary.md)*
