-- pgTAP: run_daily_cron_for_date — close tournament, penalties, idempotency, auto-forfeit (§1)
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(10);

-- Stable UUIDs
-- ua = aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1, ub = bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2

DELETE FROM public.daily_submissions
WHERE user_id IN (
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1'::uuid,
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2'::uuid
);
DELETE FROM public.tournament_scores
WHERE tournament_id IN (SELECT id FROM public.tournaments WHERE name LIKE 'tier_a_cron_%');
DELETE FROM public.tournament_participants
WHERE tournament_id IN (SELECT id FROM public.tournaments WHERE name LIKE 'tier_a_cron_%');
DELETE FROM public.tournaments WHERE name LIKE 'tier_a_cron_%';
DELETE FROM public.users WHERE id IN (
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1'::uuid,
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2'::uuid
);
DELETE FROM auth.users WHERE id IN (
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1'::uuid,
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2'::uuid
);

INSERT INTO auth.users (id, email, aud, role, created_at, updated_at, is_sso_user, email_confirmed_at)
VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1'::uuid, 'tier_a_cron_a@test.invalid', 'authenticated', 'authenticated', now(), now(), false, now()),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2'::uuid, 'tier_a_cron_b@test.invalid', 'authenticated', 'authenticated', now(), now(), false, now());

INSERT INTO public.users (id, display_name)
VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1'::uuid, 'TierA Cron A'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2'::uuid, 'TierB Cron B')
ON CONFLICT (id) DO NOTHING;

-- 1) Step 3: active tournament past end_date closes on cron
INSERT INTO public.tournaments (id, name, join_code, start_date, end_date, status, created_by)
VALUES (
  'f0000001-0001-0001-0001-000000000001'::uuid,
  'tier_a_cron_close',
  'TACLOSE1',
  '2025-01-01',
  '2025-01-05',
  'active',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1'::uuid
);
INSERT INTO public.tournament_participants (tournament_id, user_id)
VALUES ('f0000001-0001-0001-0001-000000000001'::uuid, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1'::uuid);

SELECT lives_ok(
  $$SELECT public.run_daily_cron_for_date('2025-01-05'::date)$$,
  'run_daily_cron_for_date lives for close scenario'
);

SELECT results_eq(
  $$SELECT status FROM public.tournaments WHERE id = 'f0000001-0001-0001-0001-000000000001'::uuid$$,
  $$VALUES ('closed'::text)$$,
  'tournament closes when end_date <= p_run_date'
);

-- 2) Penalty: active day in range, no submission today -> one penalty row after cron
INSERT INTO public.tournaments (id, name, join_code, start_date, end_date, status, created_by)
VALUES (
  'f0000002-0002-0002-0002-000000000002'::uuid,
  'tier_a_cron_penalty',
  'TACLOSE2',
  '2025-02-01',
  '2025-02-28',
  'active',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1'::uuid
);
INSERT INTO public.tournament_participants (tournament_id, user_id)
VALUES ('f0000002-0002-0002-0002-000000000002'::uuid, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2'::uuid);

SELECT lives_ok(
  $$SELECT public.run_daily_cron_for_date('2025-02-10'::date)$$,
  'run_daily_cron_for_date lives for penalty scenario'
);

SELECT is(
  (SELECT count(*)::integer
   FROM public.daily_submissions
   WHERE user_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2'::uuid
     AND submission_date = '2025-02-10'::date
     AND submission_text = 'NO SUBMISSION - PENALTY'),
  1,
  'missing submission inserts single penalty row for run date'
);

-- 3) Idempotency: second run same date does not add duplicate penalty
SELECT lives_ok(
  $$SELECT public.run_daily_cron_for_date('2025-02-10'::date)$$,
  'second run same p_run_date succeeds'
);

SELECT is(
  (SELECT count(*)::integer
   FROM public.daily_submissions
   WHERE user_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2'::uuid
     AND submission_date = '2025-02-10'::date
     AND submission_text = 'NO SUBMISSION - PENALTY'),
  1,
  'penalty row still exactly one after idempotent cron'
);

-- 4) Auto-forfeit: tournament age >= N and last N days in window each have penalty
INSERT INTO public.tournaments (id, name, join_code, start_date, end_date, status, created_by)
VALUES (
  'f0000003-0003-0003-0003-000000000003'::uuid,
  'tier_a_cron_forfeit',
  'TACLOSE3',
  '2025-03-01',
  '2025-03-31',
  'active',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1'::uuid
);
INSERT INTO public.tournament_participants (tournament_id, user_id)
VALUES ('f0000003-0003-0003-0003-000000000003'::uuid, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2'::uuid);

INSERT INTO public.daily_submissions (user_id, submission_date, submission_text, wordle_score)
VALUES
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2'::uuid, '2025-03-01', 'NO SUBMISSION - PENALTY', -2),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2'::uuid, '2025-03-02', 'NO SUBMISSION - PENALTY', -2);

SELECT lives_ok(
  $$SELECT public.run_daily_cron_for_date('2025-03-03'::date)$$,
  'cron on third day adds penalty then may auto-forfeit'
);

SELECT is(
  (SELECT forfeited FROM public.tournament_participants
   WHERE tournament_id = 'f0000003-0003-0003-0003-000000000003'::uuid
     AND user_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2'::uuid),
  true,
  'participant auto-forfeited after N penalty days in tournament window'
);

-- 5) Young tournament: not enough tournament age -> no auto-forfeit even with global penalties
INSERT INTO public.tournaments (id, name, join_code, start_date, end_date, status, created_by)
VALUES (
  'f0000004-0004-0004-0004-000000000004'::uuid,
  'tier_a_cron_young',
  'TACLOSE4',
  '2025-04-03',
  '2025-04-30',
  'active',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1'::uuid
);
INSERT INTO public.tournament_participants (tournament_id, user_id)
VALUES ('f0000004-0004-0004-0004-000000000004'::uuid, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1'::uuid);

-- No pre-seeded penalties: tournament is only one day old; cron may insert today's penalty only.

SELECT lives_ok(
  $$SELECT public.run_daily_cron_for_date('2025-04-03'::date)$$,
  'cron on first eligible day for young tournament runs'
);

SELECT is(
  (SELECT forfeited FROM public.tournament_participants
   WHERE tournament_id = 'f0000004-0004-0004-0004-000000000004'::uuid
     AND user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1'::uuid),
  false,
  'young tournament (age < N-1 days) does not auto-forfeit'
);

SELECT * FROM finish();
ROLLBACK;
