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