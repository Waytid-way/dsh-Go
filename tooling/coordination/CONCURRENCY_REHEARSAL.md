# Overlapping-transaction claim rehearsal

**Scope:** isolated Supabase development project `dsh-go-coordination-dev`. Do not run on production. This verifies PostgreSQL row-lock exclusion for `coordination.claim_work`; it does not verify an actual ChatGPT Scheduled Task identity, a network JWT signature, or GitHub reconciliation.

## Observed result (2026-11-20, Asia/Bangkok)

Temporary `pg_cron` jobs ran two independent PostgreSQL backends against the same synthetic work item, with `pg_sleep(4)` holding both transactions open.

| Worker | PID | Started UTC | Finished UTC | Outcome |
| --- | ---: | --- | --- | --- |
| race-a | 16536 | 2026-11-19 19:01:16.990475 | 19:01:20.999275 | CLAIMED, generation 1 |
| race-b | 16535 | 2026-11-19 19:01:16.991696 | 19:01:20.996932 | UNAVAILABLE |

**Proof properties:** distinct backend PIDs; interval overlap ~4 s; exactly one successful claim. The losing outcome is `UNAVAILABLE` because `FOR UPDATE SKIP LOCKED` skips a row held by the other transaction. A run where the second starts after the first commit is **not** sufficient concurrency evidence.

## Reproduction protocol

Run each stage as a **separate committed SQL call**. Do not concatenate all stages into a single transaction: Cron cannot run a newly scheduled job until the scheduling transaction commits. The credentials below are synthetic UUIDs passed only to a trusted SQL fixture; **they are not actual Auth users and do not prove signed JWT authentication**.

### Stage 1 — fixture and scheduling capability

Verify `pg_cron` was not already installed and that there are no existing Cron jobs before running this experiment. Never uninstall an extension that another workload uses. These statements were executed in a fresh project where Cron was previously absent.

```sql
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
GRANT USAGE ON SCHEMA cron TO postgres;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA cron TO postgres;

CREATE TABLE coordination.race_probe (
 worker_id text PRIMARY KEY,
 backend_pid integer NOT NULL,
 started_at timestamptz NOT NULL,
 finished_at timestamptz,
 outcome text,
 lease_generation bigint
);
ALTER TABLE coordination.race_probe ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON coordination.race_probe FROM public, anon, authenticated;

INSERT INTO coordination.programs(program_key,cutoff_at,accept_new_claims)
VALUES ('race-check','2099-01-01T00:00:00Z',true);
INSERT INTO coordination.domains(id,description,enabled)
VALUES ('race-check','isolated overlapping-session claim experiment',true);
INSERT INTO coordination.worker_identities(worker_id,auth_user_id,domain_id,enabled) VALUES
 ('race-a','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','race-check',true),
 ('race-b','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','race-check',true);
INSERT INTO coordination.work_items(repository,issue_number,domain_id,program_key,issue_revision)
VALUES ('fixture/cron-race',900123,'race-check','race-check','fixed-revision');
SELECT id FROM coordination.work_items WHERE repository='fixture/cron-race' AND issue_number=900123;
```

Use the returned synthetic work item ID in Stage 2. The observed run used ID `7`. The ID is not stable across replays.

### Stage 2 — start two independent database workers

Prepare **two** `DO` commands identical except worker name and UUID:

```sql
DO $race$
DECLARE v_out text; v_gen bigint;
BEGIN
 IF EXISTS(SELECT 1 FROM coordination.race_probe WHERE worker_id='race-a')
 THEN RETURN; END IF;
 PERFORM set_config('request.jwt.claim.sub',
   'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',true);
 INSERT INTO coordination.race_probe(worker_id,backend_pid,started_at)
 VALUES ('race-a',pg_backend_pid(),clock_timestamp());
 SELECT outcome,lease_generation INTO v_out,v_gen
 FROM coordination.claim_work(
   /* replace with fixture ID */ 7,'fixed-revision',900);
 PERFORM pg_sleep(4);
 UPDATE coordination.race_probe
 SET finished_at=clock_timestamp(),outcome=v_out,lease_generation=v_gen
 WHERE worker_id='race-a';
END $race$;
```

Do not run the `DO` command directly. Pass it as the quoted `command` argument to:

```sql
SELECT cron.schedule('dsh-race-a','5 seconds',$cmd$<race-a DO command>$cmd$);
SELECT cron.schedule('dsh-race-b','5 seconds',$cmd$<race-b DO command>$cmd$);
```

Here `<race-a DO command>` denotes the entire preceding `DO` command, and the `race-b` form substitutes `race-b` and `bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb`. Cron creates distinct connections for different jobs. Each job checks for a pre-existing result and returns on later runs. Limit the experiment to these two jobs; stop the jobs as soon as one record per worker exists.

### Stage 3 — assert overlap, not just exit status

```sql
SELECT worker_id,backend_pid,started_at,finished_at,outcome,lease_generation
FROM coordination.race_probe ORDER BY worker_id;
```

Require two rows with distinct PIDs and fully populated time intervals satisfying
`greatest(a.started_at,b.started_at) < least(a.finished_at,b.finished_at)`.
Require exactly one `CLAIMED` and **no second `CLAIMED`**. The losing result may be `UNAVAILABLE` while the row is locked; if it is `CONFLICT`, verify that the time intervals genuinely overlapped before accepting the result.

### Stage 4 — cleanup (mandatory)

Unschedule first; verify both jobs are absent before deleting fixtures. If any other Cron jobs existed before the test, **do not drop pg_cron**.

```sql
SELECT cron.unschedule('dsh-race-a'),cron.unschedule('dsh-race-b');
SELECT COUNT(*) FROM cron.job
WHERE jobname IN ('dsh-race-a','dsh-race-b');
-- Must return 0.

BEGIN;
DELETE FROM coordination.evidence_records
 WHERE run_id IN (SELECT id FROM coordination.worker_runs
   WHERE work_item_id IN (SELECT id FROM coordination.work_items
     WHERE repository='fixture/cron-race'));
UPDATE coordination.work_leases SET run_id=NULL
 WHERE work_item_id IN (SELECT id FROM coordination.work_items
   WHERE repository='fixture/cron-race');
DELETE FROM coordination.work_leases WHERE work_item_id IN
 (SELECT id FROM coordination.work_items WHERE repository='fixture/cron-race');
DELETE FROM coordination.worker_runs WHERE work_item_id IN
 (SELECT id FROM coordination.work_items WHERE repository='fixture/cron-race');
DELETE FROM coordination.work_items WHERE repository='fixture/cron-race';
DELETE FROM coordination.worker_identities WHERE worker_id IN ('race-a','race-b');
DELETE FROM coordination.domains WHERE id='race-check';
DELETE FROM coordination.programs WHERE program_key='race-check';
DROP TABLE coordination.race_probe;
COMMIT;
```

If the extension was newly installed for this rehearsal **and no unrelated jobs exist**, run `DROP EXTENSION pg_cron;` and verify its absence.

The observed cleanup verified: 0 Cron jobs, 0 work items, 0 leases, 0 registered worker identities, 0 enabled domains, 0 programs accepting claims; extension uninstalled. Keep recorded evidence in GitHub, not a live fixture database.

## Identity caveat

The connected Supabase management tool's SQL session reported `session_user=postgres`, `current_user=postgres`, `auth.uid()=NULL`. Its permissions are for administration. **Do not use task-defined strings or synthetic SQL session settings as proof of which ChatGPT Automation called.** The remaining integration gate requires a signed worker identity that can be bound to an authenticated network request, or a separate trusted gateway with independently provisioned secrets.
