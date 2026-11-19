# Phase 0 capability proof: ChatGPT-native identity and write isolation

**Date:** 2026-11-20 (Asia/Bangkok)  
**Authorization:** Investigate and document Phase 0 only; no credential changes, no new/scheduled tasks, no database writes, no deployment.  
**Status:** **BLOCKED / NOT_VERIFIED** for enabling privileged domain workers. Database-only concurrency proof is retained as **PASS**.

Related: [ADR-001](ADR-001-chatgpt-native.md), [decision issue #15](https://github.com/Waytid-way/dsh-Go/issues/15), [lease/identity #17](https://github.com/Waytid-way/dsh-Go/issues/17), [reconciliation #18](https://github.com/Waytid-way/dsh-Go/issues/18), [D1 pilot #19](https://github.com/Waytid-way/dsh-Go/issues/19).

## Questions and minimum proofs

| Question | Required conclusive proof | Current result |
| --- | --- | --- |
| Can two ChatGPT Scheduled Tasks present *distinct* signed principals to Gateway? | Two separately scheduled Task invocations send verifiable signatures and receive distinct server-verified subjects without secrets in prompts | **NOT_VERIFIED** |
| Can a Task impersonate a peer by sending a worker ID or domain? | Actual network negative test rejects forged identity, wrong domain and revoked token | **NOT_RUN** |
| Can a Worker bypass gateway using its existing GitHub connector? | Task-scoped provider/tool permissions demonstrate denial of direct write; attempt from worker Task receives denial | **NOT_VERIFIED** |
| Can shared Supabase management SQL be used as an authenticated worker? | DB principal has authenticated, distinct Task subject, not admin | **FAIL for current connection** |
| Is current Supabase dev safely inactive? | Read-only state and functions inspection | **PASS for observed state** |
| Did PostgreSQL exclude overlapping work claims? | Independent overlapping backend sessions, one winner | **PASS, prior bounded test** |

## Observations (read-only)

### ChatGPT Automations

The Scheduled Automation listing shows:

- `DSH Go engineering loop` ID `6aff35740b788191b4a3896a247add68`, enabled, environment selection `inherited`, environments `null` (details not exposed).
- `DSH Go final audit` ID `6aff35e4f8388191be78d390a6e5b88f`, enabled, environment selection `inherited`, environments `null`.
- No change to either automation was made.

The automation listing does not report an independently signed identity, per-Task OAuth binding or per-Task GitHub tool write policy. An attempt to use the separate automation-definition getter returned `404 Action not found`; the read-only listing succeeded. This is a **tool observation**, not proof that a distinct identity feature is impossible.

### Connected-app permission configuration

Current user-connected GitHub app: **App-specific 'Allow all actions'**; default is 'Allow low-risk actions'.

Current user-connected Supabase app: **App-specific 'Allow all actions'**; default is 'Allow low-risk actions'.

These settings concern the connected app/account, not demonstrated Task-specific worker principals. The current chat has both read and write actions available via connected tools. Availability in this chat does not establish whether an individual scheduled Task can invoke each action, but it makes bypass prevention an explicit acceptance gate. We did not change app permissions, because such changes could affect the existing engineering loop.

Public OpenAI documentation describes Scheduled Task access in terms of connected accounts, app permissions, and workspace controls; it does not establish a cryptographic per-Task identity for multiple tasks sharing one app connection:

- https://help.openai.com/en/articles/10291617-scheduled-tasks-in-chatgpt
- https://help.openai.com/en/articles/20001495-managing-app-permissions-in-chatgpt
- https://help.openai.com/en/articles/11487775-connected-apps-in-chatgpt

### Supabase dev runtime

Read-only SQL:

```sql
select current_user, session_user, auth.uid();
select count(*) from coordination.worker_identities;
select count(*) from coordination.work_items;
select count(*) from coordination.domains where enabled;
select program_key, cutoff_at, accept_new_claims
from coordination.programs
where program_key = 'dsh-go';
```

Results:

- `current_user = postgres`, `session_user = postgres`, `auth.uid() = NULL`.
- Worker identities: **0**. Work items: **0**. Enabled operational domains: **0**.
- Program `dsh-go` accepts new claims: **false**.
- Cutoff: `2026-11-21 02:00:00+00` / 09:00 Asia/Bangkok.
- Supabase Edge Functions list: empty (`[]`). No gateway deployed.

This connected SQL channel is an administrator, **not** a worker-specific principal. The underlying DB lease function's simulated JWT claim tests do **not** establish signed network identity.

The previous overlapping PostgreSQL race test reported distinct backend PIDs `16536`/`16535` and exactly one `CLAIMED`, one `UNAVAILABLE`; details are in [CONCURRENCY_REHEARSAL.md](CONCURRENCY_REHEARSAL.md). This test is not rerun in Phase 0 and is not an identity proof.

### Supabase authentication documentation

Supabase Edge Functions support `withSupabase({ auth: 'user' })` with verified user JWT and separate named secret-key modes. Server secret keys bypass RLS and must remain backend-only. Function modes establish an interface *if the caller has its own usable credential*, not an identity for ChatGPT Tasks by themselves.

- https://supabase.com/docs/guides/functions/auth
- https://supabase.com/docs/guides/getting-started/migrating-to-new-api-keys
- https://supabase.com/docs/guides/api/securing-your-api

## Phase 0 exit criterion and conclusion

**Phase 0 is not complete for enabling the gateway or workers.** We can validate the database component, but not the required boundary between each Scheduled Task and its claimed worker identity. Nor can we show that an authorized ChatGPT Task has no direct GitHub write bypass.

The following must be observed before Phase 1 authorization is proposed:

1. Two separately scheduled Task contexts invoke a *no-side-effect* challenge endpoint with independently verifiable principals. A plaintext `worker_id` in the request or in a prompt does not count.
2. The server rejects invalid, stolen/revoked, mismatched-domain and wrong-task assertions; credential material stays out of prompts/logs/public GitHub.
3. A Worker Task cannot call direct GitHub write operations except through its designated authorized gateway. Verify from a real Task permission context, not a general account permission description.
4. Evidence records include authenticated subject, test request ID, timestamp, expected vs actual status, and attributable Task context.

If there is no platform-supported secure mechanism for points 1 and 3, the target ChatGPT-native privileged-worker design remains **BLOCKED**. A separate explicit architecture change would be required to use external Workers or a human-controlled write path instead.

## Changes made / not made in Phase 0

- Added an ADR and this evidence record on the isolated development branch.
- No SQL mutations, Edge Function deployments, identity issuance, permission changes, new tasks, edits to existing tasks, GitHub main/PR operations or production changes.
- Program claims and operational domains remain disabled.

**This report records findings, blockers and the next reproducible tests. It does not report a PASS for tests not executed.**
## Additional Phase 0 evidence: actual Scheduled Task GitHub write

**Observed from independent sources, 2026-11-20:** The existing `DSH Go engineering loop` recorded a completed run scheduled for `2026-11-19T19:00:00Z` (02:00 Asia/Bangkok), whose automation result reported posting evidence to GitHub Issue #6. A separate GitHub connector read found the actual comment at [Issue #6 comment 7019117047](https://github.com/Waytid-way/dsh-Go/issues/6#issuecomment-7019117047) with the described checkpoint content. The run's `requires_user_action` flag was `false`.

**Inference with evidence:** The automation run reported an external GitHub Issue Comment write, and that same comment exists in GitHub under the connected account. This is strong corroboration of the task-originated write, but the GitHub author is the account user, **not a cryptographically identified Task ID**; the comment itself cannot independently prove which Task authored it. This confirms a real external-write path that does not pass through the planned Supabase Gateway. It does not establish what credentials every other Task would receive, and does not prove that per-Task restrictions are impossible. However, even if a future Gateway verifies distinct worker principals, this existing write capability must be blocked or constrained for workers that should not bypass the Gateway.

### Capability boundary and alternatives

An authorization service cannot distinguish two callers if they present the **same trusted principal, same effective permissions, and no independently verifiable task claim**. A `task_id`, `worker_id`, domain name or idempotency key supplied as ordinary text cannot resolve the ambiguity. Supabase JWT verification proves the caller identified by the JWT; it does not by itself prove which ChatGPT Task used a shared app connection.

Official ChatGPT product documentation currently establishes:
- [Scheduled tasks](https://help.openai.com/en/articles/10291617-scheduled-tasks-in-chatgpt) use connected apps with account/workspace permissions and approvals; it does **not** document separately signed per-task principals for tasks sharing one connection.
- [Sharing scheduled tasks](https://help.openai.com/en/articles/7925741-sharing-conversations-and-scheduled-tasks-in-chatgpt) lets recipients schedule separate copies using *their own connected accounts*. This could provide separate account-level identities if operated by separate authorized users; not verified or authorized for this project.
- [Workspace Agents for Business and Enterprise](https://help.openai.com/en/articles/20001143-chatgpt-workspace-agents-for-enterprise-and-business) support schedules and agent-level tool/connection safety controls. This is a **different agent runtime and eligible workspace feature**, not proof of per-Task isolation for current Scheduled Tasks. Replacing runtime would require a new architecture decision and access review.

**Candidate follow-ups, ordered by least disruption:**

1. **No-change research mode:** keep existing DSH Go loop, but do **not** claim it is strongly isolated or appoint it as D1–D4. Continue analysis/review work and manual scrutiny under its existing limits.
2. **Account-level write approval (requires separate approval):** changing GitHub app-specific permission from `Allow all actions` to `Ask before writes` would likely add human confirmation for mutating actions but affects the existing loop and **is not per-task identity separation**. Confirm product behavior before relying on it.
3. **Separate owner identities (requires new users/connections and authorization):** recipients of shared tasks use their own app accounts. Distinct principals may then be available at account boundary; tests still need to demonstrate task-to-gateway authentication and no-write bypass.
4. **Workspace Agents (requires eligible managed workspace and change of ADR):** test per-agent action constraints and dedicated agent-owned connections with schedules. These controls may address write scope but still need an authenticated Gateway subject and negative tests.

### Updated stopping rule

In the *current single-connected-account configuration*, the available evidence establishes an actual Scheduled Task GitHub write path but does not expose task-specific principals or task-specific deny rules. There is no authorized way, within this read-only Phase 0 scope, to exercise two independently signed Task-to-Gateway calls or to test a task-scoped write denial without changing identity, app permissions, Tasks, or deployment.

Accordingly, **Phase 0 capability investigation is complete within the approved non-mutating test scope, but the Phase 0 exit gate is BLOCKED**. Do not treat further documentation-only SQL tests as progress toward that exit gate. Next progress requires an explicit authorization to change the runtime/identity/permissions test setup, not more Postgres concurrency tests.

## Continued first-principles review: separating identity and authority (2026-11-20)

### Proven access boundary

Read-only GitHub connector calls on `Waytid-way/dsh-Go` observed:
- `get_repo` reports the linked user has `admin=true`, `push=true`, `maintain=true`, `pull=true`, and `triage=true`.
- `GET /repos/Waytid-way/dsh-Go/rulesets` returned an empty list (`[]`). This indicates **no repository rulesets returned at inspection**, not proof that no other policy exists.
- `GET /repos/Waytid-way/dsh-Go/branches/main/protection` returned `403 Resource not accessible by integration`. The state of legacy branch protection is **UNKNOWN**, not necessarily absent.

These observations cannot establish which precise actions a particular scheduled run can call. The previously observed successful Issue #6 comment provides one concrete externally visible write via the scheduled workflow.

Official GitHub docs confirm repository rulesets can restrict branch creation and updates and can require PRs or checks, but they are not a per-task identity system and do not protect all issue/comment operations:
https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets

### Indistinguishability constraint

If Task A and Task B possess the same independently authenticated provider credential and have the same effective permissions, a gateway cannot distinguish them solely from identical valid requests. Ordinary payload values such as `task_id`, `worker_id`, `domain`, time windows, and idempotency keys can be copied or forged by either task. A nonce helps freshness but not source attribution. A JWT that represents only the **shared connection** proves connection identity, not which Task sent the request.

This gives two distinct requirements:

1. **Execution safety:** workers lack independent paths to privileged writes outside the permitted writer.
2. **Worker accountability:** claims, renewals and domain assignments are bound to a verifiable per-worker principal.

Execution safety can be established at a *capability boundary* without cryptographically proving a worker identity **if** every worker has only limited upstream authority and the writer separately verifies and approves commands. However, **strong per-domain worker isolation** still requires distinguishable principals or hard task-level tool/access restrictions.

### Proposed ADR amendment, not yet approved

A practical alternative after the existing engineering loop and final read-only audit have finished is:

1. **Worker-side constrained authority:** establish a truly read-only GitHub connection at the provider/tool-action level for all advisory ChatGPT workers. Merely changing 'Allow all actions' to 'Ask before writes' is approval policy, not true permission reduction. Preserve the current connection and automation behavior until a separately approved transition.
2. **Untrusted proposal queue:** workers submit suggested changes or evidence as untrusted data. A shared connection or ordinary textual worker label is *not* a trusted provenance claim. Queue submission grants no GitHub write authority.
3. **Single trusted writer:** human-authorized operation with a dedicated least-privilege GitHub App/service credential (separate from worker credentials). It checks allowed repo, branch, operation, current HEAD, test evidence and immutable approval before write, then reconciles unknown outcomes. Start with human approval for every write.
4. **Deferred per-worker claims:** do not enable Supabase worker-specific claim RPCs until genuine per-worker identity is demonstrated. A centralized coordinator may track proposals without pretending to know a cryptographically authenticated task source.
5. **Source-side rules:** once authorized, consider GitHub rulesets for protected branch patterns to prevent bypass even if an execution component misbehaves. Verify with protected-branch and direct-write denial tests. Rulesets alone do not isolate issue writes or arbitrary development branches.

This preserves ChatGPT-native *analysis* and can restore some multi-agent throughput through parallel proposals, while acknowledging lower autonomy and uncertain task attribution. It is **not** the fully approved strong-isolation execution architecture and requires a new decision before changing permissions, app connections, creating a writer credential, or deploying anything.

### Alternatives requiring separate authorization

- **Workspace Agents (Business/Enterprise):** official docs describe schedules, agent-owned connections, tool selection, action constraints and per-agent approval policy. This is a distinct product/runtime; eligibility on this account has not been verified. https://help.openai.com/en/articles/20001143-chatgpt-workspace-agents-for-enterprise-and-business
- **Separate accounts / recipients of shared Scheduled Tasks:** recipients run copies under their own connected account and permissions. This provides account-level separation but introduces account/operational overhead and still requires signed gateway integration proof. https://help.openai.com/en/articles/10291617-scheduled-tasks-in-chatgpt

### Updated conclusion

**Current model:** do not start multi-domain workers, claim network auth PASS, or enable gateway writes.

**Available next useful experiment:** a scoped, non-production **capability-denial rehearsal**, not another database lease test. It should verify a proposed worker's GitHub write call is denied by provider/task controls and a separate authorized writer can perform only explicitly allowed writes. The existing engineering loop and 09:30 final audit should be preserved until complete. Credential, connection, policy, or automation changes require human approval.

**Status:** proposed design refinement; no policy or runtime mutation performed.
