# ADR-001: ChatGPT-native engineering coordination

- **Status:** Accepted as a design baseline for Phase 0 only (2026-11-20)
- **Implementation authorization:** Phase 0 capability investigation only. Phases 1-4 require separate gate approval.
- **Repository:** `Waytid-way/dsh-Go`
- **Supabase development project:** `dsh-go-coordination-dev` / `tcwlebixkpgvpqijpuqw`
- **Decision record:** [#15](https://github.com/Waytid-way/dsh-Go/issues/15)
- **Evidence:** [PHASE0_CAPABILITY_PROOF.md](PHASE0_CAPABILITY_PROOF.md)

## Problem and goals

Run independent ChatGPT Scheduled Tasks as domain-focused engineering workers without overlapping claims, stale GitHub writes, impersonation, or unverifiable evidence. Priorities: correctness, domain specialization, recoverability, then increased throughput.

The original DSH Go engineering loop cutoff is **2026-11-21 09:00 Asia/Bangkok**. A later pilot needs its own program, scope, budget and deadline. Do not change the original loop or final audit task as part of this ADR.

## Decision

Retain ChatGPT Scheduled Tasks as the proposed worker runtime. Reuse the private Supabase coordination database for *development-only* atomic claim and evidence bookkeeping. GitHub remains the source of truth for issue, branch, commit, CI and engineering evidence.

Choose a **two-mode design**:

1. **Research mode:** workers produce plans, reviews and read-only results. Read-only must be enforced by actual connected-app/provider capabilities; a prompt asking the agent not to write is *not* isolation. If those capabilities cannot be restricted, do not assert research-mode security.
2. **Authenticated execution mode:** only after verifiable per-worker identity and no GitHub-write bypass exists, workers can claim tasks and request precisely authorized mutations through a narrowly scoped trusted gateway.

**Target deployment if and only if feasible:** Supabase Edge Functions gateway. Its existence alone does not solve Task identity, authorizations or bypass prevention. All operational domains and claim acceptance remain disabled until exit gates pass.

## Trust boundaries and ownership

| Owner | Owns | Must not be trusted for |
| --- | --- | --- |
| ChatGPT worker | Analysis and proposed work result | Self-asserted worker ID, domain or approval |
| Coordinator | Work selection, dependency analysis, checking results | Granting itself or workers new privileges |
| Trusted gateway | Verifying principals; authorization, revocation, operation intent, external result tracking | Caller-supplied identity strings |
| PostgreSQL `coordination` | Atomic leases, monotonic generation, deadline, evidence ledger, audit | GitHub truth or unverified caller identity |
| GitHub | Live issue/branch/commit/CI state | Database lease ownership |
| Human supervisor | Scope, privilege expansion, sensitive writes, incident exception decisions | Implicit approvals embedded in prompts |

A privileged Supabase service/admin connection that bypasses RLS **must never** accept a caller's `worker_id` or a freely supplied session claim as authoritative. Authenticated principal propagation into PostgreSQL requires an independently reviewable proof before the gateway can mutate coordination records.

## Minimum contracts

Normal workflow, only after gates:

1. `getWork`: authenticated, scoped read.
2. `claimWork(workItemId, expectedRevision)`: verify live GitHub state, then atomic DB claim, bounded by program cutoff.
3. `renewLease` and `releaseWork`: owner and generation checks.
4. `recordEvidence`: idempotent append; distinguish worker-reported results from independently verified evidence.
5. `requestWrite`: authorized operation + expected live GitHub SHA + durable intent, with an actual stale-write rejection on GitHub.
6. `reconcileWork`: inspect external effects before retries or reclaim.

No generic SQL execution or arbitrary GitHub operation endpoint. The caller may submit a candidate work item but cannot establish authorization by claiming an identity in the payload.

### GitHub write correctness

The pre-write SHA read cannot alone prevent a concurrent update. Use a GitHub operation that rejects concurrent/stale state at the point of mutation, and prove behavior with a two-writer test. Record an idempotency key and operation intent before the external call. On timeout after submission, treat the result as `UNKNOWN_EXTERNAL_OUTCOME`, query GitHub, and reconcile before retrying. Do **not** promise exactly-once GitHub mutation.

Any worker with a direct GitHub write connector or sufficiently broad provider credential can bypass a gateway. Disabling write tools in prompt text is not a permission boundary. Verify provider-side and task-scoped restrictions before claiming gateway enforcement.

### Recovery

An expired lease becomes `RECONCILIATION_REQUIRED`, not immediately claimable. Verify external side effects and evidence first. Reclaim only when the absence of conflicting effects is established. Conflicts or unknown outcomes require human review.

Use item-level or domain-level pauses for localized errors; stop all new claims and privileged writes on identity/authorization or coordination-integrity incidents. Gateway denies coordinator overrides without independent authorization.

### Credential and audit contract

Identity may be independently signed user JWT or independently verified platform attestation. It must map server-side to an enabled worker and domain. Prefer short-lived delegated, operation-scoped authority with revocation checked at impact-bearing operations. Do not embed tokens in prompts, issues, code or logs. Store operational audit for 90 days with incident hold; engineering evidence follows repository policy.

## Alternatives

- **Direct shared ChatGPT connectors:** low infrastructure cost; rejected for privileged multi-worker coordination because per-task authentication and bypass prevention have not been established.
- **ChatGPT + gateway:** target conditional design; requires proof of authenticated task identity and connector isolation.
- **ChatGPT research + human-controlled writes:** possible interim workflow, but cannot be labeled read-only without real write-permission controls.
- **External worker runtime:** provides stronger control over credentials but conflicts with the currently approved ChatGPT-native requirement; not authorized here.

## Deployment sequence and exit gates

| Phase | Scope | Exit evidence |
| --- | --- | --- |
| **0: capability proof (authorized)** | Determine if distinct Task principals can authenticate securely; prove task-scoped GitHub write denial/bypass prevention | Real authenticated invocations from distinct Task contexts and verified deny tests; otherwise BLOCKED with evidence |
| 1: gateway prototype (not authorized) | Limited private Edge Function interface, identity propagation, negative auth tests | Invalid/revoked/other-domain identities denied through actual network requests |
| 2: GitHub adapter (not authorized) | Conditional writes, durable ledger, retry and external reconciliation | Stale revision, concurrent writer and unknown-result tests pass |
| 3: D1 pilot (not authorized) | Separate bounded program, one worker and one work item, rollback | End-to-end claim, verify, evidence, failure and rollback |
| 4: expansion (not authorized) | Add domains and bounded concurrency | Cross-domain denial, invariants and budget tests |

## Verified vs unverified

- **PASS:** concurrent PostgreSQL session exclusion: one CLAIMED, one UNAVAILABLE; lease fencing and DB-local evidence tests.
- **BLOCKED:** distinct cryptographic ChatGPT Task identity and task-scoped GitHub write isolation.
- **NOT_RUN:** real Task-to-Gateway signed identity test, revocation network test and gateway bypass-denial test.
- **NOT_IMPLEMENTED:** verified GitHub adapter, external effect reconciliation and multi-domain rollout.

See [PHASE0_CAPABILITY_PROOF.md](PHASE0_CAPABILITY_PROOF.md) for current dated observations and test limits.

## Safety invariants

Do not modify `main`, scheduled automations, production resources, provider permissions or connected accounts in Phase 0. Do not issue credentials, create worker tasks, deploy gateway functions, create production access, open domains or enable new claims without the appropriate later gate approval. Existing Supabase schema and test proof may be reused, but passing database tests does not imply authenticated task execution.