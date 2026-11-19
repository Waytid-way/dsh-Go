-- Run only against the isolated Supabase development project.
-- This script exercises the real coordination functions via simulated auth.uid().
-- It does NOT prove network JWT verification or simultaneous PostgreSQL sessions.
-- All fixture writes are cleaned up in the same atomic DO statement.
DO $integration$
DECLARE
  work_id bigint;
  past_id bigint;
  first_claim record;
  next_claim record;
  result record;
  evidence_result text;
BEGIN
  INSERT INTO coordination.programs(program_key,cutoff_at,accept_new_claims) VALUES
    ('contract-test-open','2099-01-01T00:00:00Z',true),
    ('contract-test-past','2000-01-01T00:00:00Z',true);
  INSERT INTO coordination.domains(id,description,enabled) VALUES
    ('contract-test-d1','Fixture',true),
    ('contract-test-other','Fixture',true);
  INSERT INTO coordination.worker_identities(worker_id,auth_user_id,domain_id,enabled) VALUES
    ('contract-test-a','11111111-1111-4111-8111-111111111111','contract-test-d1',true),
    ('contract-test-b','22222222-2222-4222-8222-222222222222','contract-test-d1',true),
    ('contract-test-other','33333333-3333-4333-8333-333333333333','contract-test-other',true);
  INSERT INTO coordination.work_items(repository,issue_number,domain_id,program_key,issue_revision)
    VALUES ('fixture/contract-test',900001,'contract-test-d1','contract-test-open','revision-A')
    RETURNING id INTO work_id;
  INSERT INTO coordination.work_items(repository,issue_number,domain_id,program_key,issue_revision)
    VALUES ('fixture/contract-test',900002,'contract-test-d1','contract-test-past','revision-A')
    RETURNING id INTO past_id;

  PERFORM set_config('request.jwt.claim.sub','',true);
  SELECT * INTO result FROM coordination.claim_work(work_id,'revision-A',900);
  IF result.outcome <> 'UNAUTHORIZED' THEN RAISE EXCEPTION 'missing identity: %',result.outcome; END IF;

  PERFORM set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',true);
  SELECT * INTO result FROM coordination.claim_work(work_id,'revision-A',900);
  IF result.outcome <> 'UNAVAILABLE' THEN RAISE EXCEPTION 'wrong domain: %',result.outcome; END IF;

  PERFORM set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
  SELECT * INTO result FROM coordination.claim_work(work_id,'revision-OLD',900);
  IF result.outcome <> 'STALE_REVISION' THEN RAISE EXCEPTION 'revision check: %',result.outcome; END IF;
  SELECT * INTO result FROM coordination.claim_work(past_id,'revision-A',900);
  IF result.outcome <> 'CUTOFF' THEN RAISE EXCEPTION 'cutoff: %',result.outcome; END IF;
  SELECT * INTO first_claim FROM coordination.claim_work(work_id,'revision-A',900);
  IF first_claim.outcome <> 'CLAIMED' OR first_claim.lease_generation <> 1
     OR first_claim.run_id IS NULL THEN RAISE EXCEPTION 'initial claim'; END IF;

  PERFORM set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true);
  SELECT * INTO result FROM coordination.claim_work(work_id,'revision-A',900);
  IF result.outcome <> 'CONFLICT' THEN RAISE EXCEPTION 'double claim: %',result.outcome; END IF;
  IF coordination.renew_lease(work_id,first_claim.lease_token,1,900)
  THEN RAISE EXCEPTION 'wrong owner renewed'; END IF;

  PERFORM set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
  IF NOT coordination.renew_lease(work_id,first_claim.lease_token,1,900)
  THEN RAISE EXCEPTION 'owner renew failed'; END IF;
  evidence_result:=coordination.record_evidence(work_id,first_claim.lease_token,1,
    'test-one','not_run','External checks intentionally NOT_RUN',null);
  IF evidence_result <> 'CREATED' THEN RAISE EXCEPTION 'create evidence: %',evidence_result; END IF;
  evidence_result:=coordination.record_evidence(work_id,first_claim.lease_token,1,
    'test-one','not_run','External checks intentionally NOT_RUN',null);
  IF evidence_result <> 'DUPLICATE' THEN RAISE EXCEPTION 'idempotency: %',evidence_result; END IF;
  evidence_result:=coordination.record_evidence(work_id,first_claim.lease_token,1,
    'test-one','pass','conflicting payload',null);
  IF evidence_result <> 'PAYLOAD_CONFLICT'
  THEN RAISE EXCEPTION 'payload conflict: %',evidence_result; END IF;
  IF NOT coordination.release_lease(work_id,first_claim.lease_token,1)
  THEN RAISE EXCEPTION 'release failed'; END IF;
  IF NOT EXISTS (SELECT 1 FROM coordination.worker_runs WHERE id=first_claim.run_id AND status='not_run')
  THEN RAISE EXCEPTION 'run status was not finalized'; END IF;

  PERFORM set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true);
  SELECT * INTO next_claim FROM coordination.claim_work(work_id,'revision-A',900);
  IF next_claim.outcome <> 'CLAIMED' OR next_claim.lease_generation <> 2
  THEN RAISE EXCEPTION 'generation did not advance'; END IF;

  PERFORM set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
  IF coordination.renew_lease(work_id,first_claim.lease_token,1,900)
  THEN RAISE EXCEPTION 'stale worker renewed'; END IF;
  evidence_result:=coordination.record_evidence(work_id,first_claim.lease_token,1,
    'stale','pass','should reject',null);
  IF evidence_result <> 'STALE_OR_UNAUTHORIZED'
  THEN RAISE EXCEPTION 'stale worker wrote evidence'; END IF;

  UPDATE coordination.work_leases SET expires_at=clock_timestamp()-interval '1 second'
    WHERE work_item_id=work_id;
  SELECT * INTO result FROM coordination.claim_work(work_id,'revision-A',900);
  IF result.outcome <> 'RECONCILIATION_REQUIRED'
  THEN RAISE EXCEPTION 'expired work was reclaimed'; END IF;

  DELETE FROM coordination.evidence_records WHERE run_id IN
    (SELECT id FROM coordination.worker_runs WHERE work_item_id IN (work_id,past_id));
  UPDATE coordination.work_leases SET run_id=null WHERE work_item_id IN (work_id,past_id);
  DELETE FROM coordination.work_leases WHERE work_item_id IN (work_id,past_id);
  DELETE FROM coordination.worker_runs WHERE work_item_id IN (work_id,past_id);
  DELETE FROM coordination.work_items WHERE id IN (work_id,past_id);
  DELETE FROM coordination.worker_identities WHERE worker_id LIKE 'contract-test-%';
  DELETE FROM coordination.domains WHERE id IN ('contract-test-d1','contract-test-other');
  DELETE FROM coordination.programs WHERE program_key IN ('contract-test-open','contract-test-past');
END $integration$;

SELECT 'PASS' AS outcome,
  has_schema_privilege('authenticated','coordination','USAGE') = false AS private_schema_restricted,
  has_function_privilege('authenticated','coordination.claim_work(bigint,text,integer)','EXECUTE') = false AS claim_execution_restricted,
  (SELECT count(*) FROM coordination.worker_identities) = 0 AS no_remaining_test_identities,
  (SELECT count(*) FROM coordination.work_items) = 0 AS no_remaining_test_work;
