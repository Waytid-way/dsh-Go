# DSH Go coordination plane (development pilot)

Status: **experimental / fail closed**. Canonical decision: [coordination contract](https://github.com/Waytid-way/dsh-Go/issues/15). Implementation tickets: [identity](https://github.com/Waytid-way/dsh-Go/issues/16), [lease verification](https://github.com/Waytid-way/dsh-Go/issues/17), [GitHub reconciliation](https://github.com/Waytid-way/dsh-Go/issues/18), [D1 pilot](https://github.com/Waytid-way/dsh-Go/issues/19).

This is **not a dependency of the mobile application or DSH runtime**. Do not add Supabase credentials to the app or repository. Supabase is only a candidate coordination plane for independently scheduled ChatGPT engineering tasks.

## Systems of record

- **GitHub** is authoritative for issues, dependencies, branch heads, commits, CI checks and engineering evidence. Database contents cannot prove a GitHub side effect.
- **Supabase** stores temporary claims, worker-to-domain assignments, run bookkeeping and pointers to evidence.
- **ChatGPT Scheduled Automations** currently continue under the existing [engineering roadmap](https://github.com/Waytid-way/dsh-Go/issues/3). No domain-specific tasks have been enabled by this work.

## Dev environment

- Supabase project: `dsh-go-coordination-dev` (Singapore), reference `tcwlebixkpgvpqijpuqw`
- Private PostgreSQL schema: `coordination`
- Main tables: `domains`, `programs`, `worker_identities`, `work_items`, `work_leases`, `worker_runs`, `evidence_records`
- Postgres functions: `claim_work(work_item_id, expected_revision, ttl_seconds)`, `renew_lease(work_item_id, token, generation, ttl_seconds)`, `release_lease(work_item_id, token, generation)`, `record_evidence(work_item_id, token, generation, idempotency_key, status, summary, github_url)`

The functions exist in Supabase migration history. The repository now contains **[bootstrap.sql](bootstrap.sql)** generated from the deployed SQL definitions, plus **[test-contract.sql](test-contract.sql)**. Bootstrap DDL was compiled in a separate test schema inside a transaction and then rolled back, with 4 domains, 1 program and 4 functions observed. **A clean Supabase project end-to-end provisioning run remains NOT_RUN.** Run bootstrap only on a fresh isolated database.

## Trusted interface and worker identity

- `auth.uid()` is mapped to exactly one enabled `worker_identities` entry and its assigned domain. The caller does not supply an authoritative worker ID.
- Claims check the domain, program cutoff, work-item state and expected issue revision.
- Functions use a narrowly scoped `SECURITY DEFINER` implementation in the private schema, with an explicit search path and authorization checks. RLS is enabled on all tables, with no client policies.
- Access is **not currently granted** to `anon` or `authenticated`; the private schema is not configured as a Data API exposure surface.
- A ChatGPT Automation's ability to present a **distinct, independently authenticated identity** is **not yet established**. Never pass a service-role key or worker credential through prompts, GitHub comments, public source files or untrusted clients.

## Lease state and fencing

A work item is available only if its domain is enabled and its program accepts claims. A successful `claim_work` atomically creates a run and lease with a random token and monotonic generation.

- Active, unexpired lease: `CONFLICT`
- Active lease that expires: `RECONCILIATION_REQUIRED` — **never automatically reclaimed**
- Explicitly released lease: eligible for a later claim with generation increased
- Invalid or expired token/generation, wrong identity or wrong domain: fail closed
- Duplicate evidence with identical payload: `DUPLICATE`; conflicting payload for the same idempotency key: `PAYLOAD_CONFLICT`

The database **cannot lock GitHub**. A legitimate worker must re-fetch the GitHub issue and branch SHA immediately before any GitHub write and stop if it observes drift. A trusted reconciliation path for crashed workers is **not implemented yet**; do not bypass expiry by directly changing lease rows without an external evidence review.

## Deadline and rollback

The `dsh-go` program cutoff is **2026-11-21 09:00 Asia/Bangkok**. `claim_work` refuses new claims at or after the cutoff and `renew_lease` refuses renewal. Evidence/release of work already recorded is possible only while a lease remains valid.

All four operational domains are currently disabled, the program does not accept new claims, and there are no registered active worker identities. To stop a future pilot: keep `programs.accept_new_claims=false`, disable the relevant domain and worker identities, and do not reconfigure the original scheduled task. Do not delete audit records as a form of rollback.

## Verification and limitations

Performed against the dev database on 2026-11-20 (Asia/Bangkok):

- SQL integration transaction: anonymous identity, wrong domain, revision conflict, cutoff, claim conflict, owner-only renewal, evidence idempotency, release, monotonic fencing and expiry quarantine passed. Fixtures removed.
- Two separate connector invocations produced one `CLAIMED` and one `CONFLICT`. **True overlapping PostgreSQL sessions were not independently demonstrated**.
- SQL privilege check: `anon` and `authenticated` have no schema usage or claim execution rights; all existing test fixtures removed.
- No independent JWT network client, cross-system GitHub reconciliation, authenticated worker pilot, Flutter checks or device checks were executed.

Gate before any multi-domain rollout: separately authenticated worker identity, repeatable overlapping-transaction test, fresh GitHub verification, reconciliation of unknown external side effects, and a bounded D1 pilot with rollback evidence.
