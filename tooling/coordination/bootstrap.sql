-- DSH Go coordination plane: development-only bootstrap (private schema).
-- Apply to a FRESH isolated Supabase database only; do not run on existing deployments.
-- Generated from actual project definition on 2026-11-20; a clean-project bootstrap has
-- NOT been executed. Use tooling/coordination/test-contract.sql for live behavior tests.
-- NO user credentials, API keys or service-role secrets belong in this repository.
CREATE SCHEMA coordination;
REVOKE ALL ON SCHEMA coordination FROM public,anon,authenticated;

CREATE TABLE coordination.programs (
  program_key text PRIMARY KEY,
  cutoff_at timestamptz NOT NULL,
  accept_new_claims boolean NOT NULL DEFAULT false
);
CREATE TABLE coordination.domains (
  id text PRIMARY KEY,
  description text NOT NULL,
  enabled boolean NOT NULL DEFAULT false
);
CREATE TABLE coordination.work_items (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  repository text NOT NULL,
  issue_number integer NOT NULL CHECK(issue_number>0),
  domain_id text NOT NULL REFERENCES coordination.domains(id),
  state text NOT NULL DEFAULT 'available'
    CHECK (state IN ('available','blocked','done')),
  issue_revision text,
  created_at timestamptz NOT NULL DEFAULT now(),
  program_key text NOT NULL DEFAULT 'dsh-go' REFERENCES coordination.programs(program_key),
  UNIQUE(repository,issue_number)
);
CREATE TABLE coordination.worker_identities (
  worker_id text PRIMARY KEY,
  auth_user_id uuid NOT NULL UNIQUE,
  domain_id text NOT NULL REFERENCES coordination.domains(id),
  enabled boolean NOT NULL DEFAULT false
);
CREATE TABLE coordination.worker_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  work_item_id bigint NOT NULL REFERENCES coordination.work_items(id),
  worker_id text NOT NULL,
  lease_generation bigint NOT NULL,
  status text NOT NULL CHECK(status IN ('running','pass','fail','not_run','blocked')),
  base_sha text,
  commit_sha text,
  started_at timestamptz NOT NULL DEFAULT now(),
  finished_at timestamptz
);
CREATE TABLE coordination.work_leases (
  work_item_id bigint PRIMARY KEY REFERENCES coordination.work_items(id),
  owner_id text NOT NULL,
  lease_token uuid NOT NULL DEFAULT gen_random_uuid(),
  generation bigint NOT NULL DEFAULT 1 CHECK(generation>0),
  expires_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  lease_status text NOT NULL DEFAULT 'active'
    CHECK(lease_status IN ('active','released','needs_reconciliation')),
  run_id uuid REFERENCES coordination.worker_runs(id)
);
CREATE TABLE coordination.evidence_records (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  run_id uuid NOT NULL REFERENCES coordination.worker_runs(id),
  idempotency_key text NOT NULL,
  status text NOT NULL CHECK(status IN ('pass','fail','not_run','blocked')),
  github_url text,
  summary text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(run_id,idempotency_key)
);

CREATE INDEX ON coordination.work_items(domain_id,state);
CREATE INDEX ON coordination.work_leases(expires_at);
CREATE INDEX ON coordination.worker_runs(work_item_id,started_at DESC);

ALTER TABLE coordination.domains ENABLE ROW LEVEL SECURITY;
ALTER TABLE coordination.programs ENABLE ROW LEVEL SECURITY;
ALTER TABLE coordination.work_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE coordination.worker_identities ENABLE ROW LEVEL SECURITY;
ALTER TABLE coordination.work_leases ENABLE ROW LEVEL SECURITY;
ALTER TABLE coordination.worker_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE coordination.evidence_records ENABLE ROW LEVEL SECURITY;

INSERT INTO coordination.programs(program_key,cutoff_at,accept_new_claims)
VALUES ('dsh-go','2026-11-21 09:00:00+07',false);
INSERT INTO coordination.domains(id,description)
VALUES ('d1','Test infrastructure'),('d2','Web host'),
       ('d3','OHOS integrity'),('d4','Architecture and portable state');

-- Functions below are pg_get_functiondef() snapshots from the deployed environment.

CREATE OR REPLACE FUNCTION coordination.claim_work(p_work_item_id bigint, p_expected_revision text, p_ttl_seconds integer DEFAULT 900)
 RETURNS TABLE(outcome text, lease_token uuid, lease_generation bigint, run_id uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'coordination'
AS $function$
declare
 v_actor coordination.worker_identities%rowtype;
 v_work coordination.work_items%rowtype;
 v_program coordination.programs%rowtype;
 v_lease coordination.work_leases%rowtype;
 v_token uuid;
 v_generation bigint;
 v_run_id uuid;
begin
 if auth.uid() is null then
   return query select 'UNAUTHORIZED'::text,null::uuid,null::bigint,null::uuid; return;
 end if;
 select * into v_actor from coordination.worker_identities
 where auth_user_id = auth.uid() and enabled=true;
 if not found then
   return query select 'UNAUTHORIZED'::text,null::uuid,null::bigint,null::uuid; return;
 end if;
 if p_ttl_seconds is null or p_ttl_seconds not between 60 and 3600
    or p_expected_revision is null or length(trim(p_expected_revision))=0 then
   return query select 'INVALID'::text,null::uuid,null::bigint,null::uuid; return;
 end if;
 select * into v_work from coordination.work_items
 where id=p_work_item_id and domain_id=v_actor.domain_id for update skip locked;
 if not found then
   return query select 'UNAVAILABLE'::text,null::uuid,null::bigint,null::uuid; return;
 end if;
 select * into v_program from coordination.programs
 where program_key=v_work.program_key;
 if not v_program.accept_new_claims or clock_timestamp() >= v_program.cutoff_at then
   return query select 'CUTOFF'::text,null::uuid,null::bigint,null::uuid; return;
 end if;
 if not exists (select 1 from coordination.domains where id=v_work.domain_id and enabled=true)
    or v_work.state <> 'available' then
   return query select 'BLOCKED'::text,null::uuid,null::bigint,null::uuid; return;
 end if;
 if v_work.issue_revision is distinct from p_expected_revision then
   return query select 'STALE_REVISION'::text,null::uuid,null::bigint,null::uuid; return;
 end if;
 select * into v_lease from coordination.work_leases
 where work_item_id=p_work_item_id for update;
 if found then
   if v_lease.lease_status <> 'released' then
     if v_lease.lease_status='needs_reconciliation'
         or v_lease.expires_at <= clock_timestamp() then
        return query select 'RECONCILIATION_REQUIRED'::text,null::uuid,null::bigint,null::uuid;
     else
        return query select 'CONFLICT'::text,null::uuid,null::bigint,null::uuid;
     end if;
     return;
   end if;
 end if;
 v_generation := coalesce(v_lease.generation,0)+1;
 v_token := gen_random_uuid();
 insert into coordination.worker_runs(work_item_id,worker_id,lease_generation,status)
 values (p_work_item_id,v_actor.worker_id,v_generation,'running')
 returning id into v_run_id;
 insert into coordination.work_leases
 (work_item_id,owner_id,lease_token,generation,expires_at,lease_status,run_id,updated_at)
 values (p_work_item_id,v_actor.worker_id,v_token,v_generation,
         clock_timestamp()+make_interval(secs=>p_ttl_seconds),'active',v_run_id,clock_timestamp())
 on conflict (work_item_id) do update set
 owner_id=excluded.owner_id,lease_token=excluded.lease_token,
 generation=excluded.generation,expires_at=excluded.expires_at,
 lease_status=excluded.lease_status,run_id=excluded.run_id,updated_at=excluded.updated_at;
 return query select 'CLAIMED'::text,v_token,v_generation,v_run_id;
end $function$;

CREATE OR REPLACE FUNCTION coordination.record_evidence(p_work_item_id bigint, p_token uuid, p_generation bigint, p_idempotency_key text, p_status text, p_summary text, p_github_url text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'coordination'
AS $function$
declare v_actor coordination.worker_identities%rowtype;
declare v_run_id uuid;
declare v_old coordination.evidence_records%rowtype;
declare v_rows integer;
begin
 select * into v_actor from coordination.worker_identities
 where auth_user_id=auth.uid() and enabled;
 if not found then return 'UNAUTHORIZED'; end if;
 if p_status not in ('pass','fail','not_run','blocked')
 or p_status is null or p_idempotency_key is null or length(trim(p_idempotency_key))=0
 or p_summary is null or length(trim(p_summary))=0 then return 'INVALID'; end if;
 select l.run_id into v_run_id from coordination.work_leases l
 join coordination.work_items w on w.id=l.work_item_id
 where l.work_item_id=p_work_item_id and w.domain_id=v_actor.domain_id
 and l.owner_id=v_actor.worker_id and l.lease_token=p_token
 and l.generation=p_generation and l.lease_status='active'
 and l.expires_at>clock_timestamp()
 for update of l;
 if not found then return 'STALE_OR_UNAUTHORIZED'; end if;
 insert into coordination.evidence_records(run_id,idempotency_key,status,summary,github_url)
 values(v_run_id,p_idempotency_key,p_status,p_summary,p_github_url)
 on conflict(run_id,idempotency_key) do nothing;
 get diagnostics v_rows=row_count;
 if v_rows=1 then return 'CREATED'; end if;
 select * into v_old from coordination.evidence_records e
 where e.run_id=v_run_id and e.idempotency_key=p_idempotency_key;
 if v_old.status=p_status and v_old.summary=p_summary
    and v_old.github_url is not distinct from p_github_url then
   return 'DUPLICATE';
 end if;
 return 'PAYLOAD_CONFLICT';
end $function$;

CREATE OR REPLACE FUNCTION coordination.release_lease(p_work_item_id bigint, p_token uuid, p_generation bigint)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'coordination'
AS $function$
declare v_actor coordination.worker_identities%rowtype;
declare v_run_id uuid;
declare v_last_status text;
begin
 select * into v_actor from coordination.worker_identities
 where auth_user_id=auth.uid() and enabled;
 if not found then return false; end if;
 update coordination.work_leases l
 set lease_status='released',expires_at=clock_timestamp(),updated_at=clock_timestamp()
 from coordination.work_items w
 where l.work_item_id=p_work_item_id and w.id=l.work_item_id
 and w.domain_id=v_actor.domain_id and l.owner_id=v_actor.worker_id
 and l.lease_token=p_token and l.generation=p_generation
 and l.lease_status='active' and l.expires_at>clock_timestamp()
 returning l.run_id into v_run_id;
 if not found then return false; end if;
 select e.status into v_last_status from coordination.evidence_records e
 where e.run_id=v_run_id order by e.created_at desc,e.id desc limit 1;
 update coordination.worker_runs
 set status=coalesce(v_last_status,'blocked'),finished_at=clock_timestamp()
 where id=v_run_id and status='running';
 return true;
end $function$;

CREATE OR REPLACE FUNCTION coordination.renew_lease(p_work_item_id bigint, p_token uuid, p_generation bigint, p_ttl_seconds integer DEFAULT 900)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'coordination'
AS $function$
declare v_actor coordination.worker_identities%rowtype;
begin
 select * into v_actor from coordination.worker_identities
 where auth_user_id=auth.uid() and enabled;
 if not found or p_ttl_seconds is null or p_ttl_seconds not between 60 and 3600 then
   return false;
 end if;
 update coordination.work_leases l
 set expires_at=clock_timestamp()+make_interval(secs=>p_ttl_seconds),
     updated_at=clock_timestamp()
 from coordination.work_items w, coordination.programs p
 where l.work_item_id=p_work_item_id and l.work_item_id=w.id
 and w.program_key=p.program_key and p.accept_new_claims and p.cutoff_at>clock_timestamp()
 and w.domain_id=v_actor.domain_id and l.owner_id=v_actor.worker_id
 and l.lease_token=p_token and l.generation=p_generation
 and l.lease_status='active' and l.expires_at>clock_timestamp();
 return found;
end $function$;
-- Private-by-default: nobody except a trusted SQL operator can invoke these until
-- authenticated per-worker network access is implemented and explicitly reviewed.
REVOKE ALL ON ALL TABLES IN SCHEMA coordination FROM public,anon,authenticated;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA coordination FROM public,anon,authenticated;
REVOKE ALL ON SCHEMA coordination FROM public,anon,authenticated;
