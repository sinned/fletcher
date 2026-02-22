# Fletcher Code Review — Principal Staff Engineer Assessment

**Date:** 2026-02-22  
**Reviewer:** Codex (Principal Staff Engineer lens)  
**Scope reviewed:** Server bootstrap and core API/MCP paths

## Executive Summary

The codebase is directionally strong (clear modular separation, Zod usage, parameterized DB access patterns), but there are several reliability and maintainability gaps that should be prioritized before scaling traffic.

**Top priorities:**
1. Refactor shared auth middleware to avoid duplicated logic and runtime dynamic imports in hot paths.
2. Normalize error handling so internal failures return 5xx (not broad 4xx) and include stable error contracts.
3. Remove implementation-comment debt and debug logging drift in production paths.

---

## Strengths

- Good use of Fastify plugin boundaries and route grouping for mobile, MCP management, and access logs.
- Validation is consistently present with Zod for user-provided payloads.
- MCP flow includes per-request token validation and access logging hooks (privacy/transparency aligned).

---

## Findings (Prioritized)

### P1 — Dynamic import in request hook on every MCP management call

**Where:** `server/src/routes/mcp_api.ts`  
Current implementation performs `await import('../models/user')` in an `onRequest` hook.

**Risk:** unnecessary per-request module resolution overhead, harder static analysis, and avoidable complexity in a latency-sensitive auth path.

**Recommendation:** import `validateAPIKey` statically at module top and reuse a shared auth helper across route plugins.

---

### P1 — Error classification mixes client and server failures

**Where:** `server/src/routes/mobile.ts` (`/register`, `/locations`, `/privacy-settings`)  
Several catch blocks return `400` for broad exceptions, including potential DB or infra faults.

**Risk:** observability blind spots and incorrect API behavior (clients retry/handle wrong class of failure).

**Recommendation:**
- Handle Zod errors as `400`.
- Map auth/lookup states to `401/404/409` as applicable.
- Default unexpected exceptions to `500` with stable error code (`INTERNAL_ERROR`).

---

### P2 — Production code contains high-noise implementation commentary

**Where:** `server/src/routes/mcp_api.ts`, `server/src/routes/mobile.ts`, `server/src/mcp/index.ts`, `server/src/index.ts`  
There are many inline conversational comments and exploratory reasoning blocks left in active source.

**Risk:** reduced readability, higher onboarding cost, and increased chance of stale comments diverging from behavior.

**Recommendation:** remove exploratory commentary from runtime files; keep architectural rationale in TDD docs under `artifacts/`.

---

### P2 — Logging consistency and shutdown lifecycle can be hardened

**Where:** `server/src/index.ts`, `server/src/db/index.ts`  
Mix of `console.log/error` and Fastify logger usage; shutdown imports DB default dynamically.

**Risk:** fragmented logs in production sinks and harder graceful-shutdown testing.

**Recommendation:**
- Standardize on Fastify logger abstractions.
- Export a typed `closeDb()` from DB module; avoid dynamic import in shutdown path.

---

### P3 — Auth middleware duplication across route plugins

**Where:** `server/src/routes/mobile.ts`, `server/src/routes/mcp_api.ts`  
Both plugins implement API key parsing/validation independently.

**Risk:** drift over time (e.g., one path gains stricter behavior while the other lags).

**Recommendation:** introduce a shared middleware utility (e.g., `server/src/middleware/api_key_auth.ts`) and apply consistently.

---

## Suggested 2-Week Hardening Plan

1. **Week 1 (Reliability):** error contract normalization + middleware extraction + remove dynamic import auth path.  
2. **Week 2 (Operational quality):** logging standardization, shutdown cleanup API, and comment debt cleanup.

Success criteria:
- API error taxonomy documented and enforced.
- No dynamic imports in request hot paths.
- Route auth behavior centrally tested and consistent.

---

## Recommended Follow-up Tests

- Add route-level tests for auth middleware behavior across `/api/*` and `/api/mcp/*`.
- Add tests validating error code/status mapping for malformed payloads vs DB failures.
- Add startup/shutdown integration test to verify DB pool closure and process exit behavior.
