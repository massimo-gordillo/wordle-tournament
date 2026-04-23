-- pgTAP: get_tournament_limit_info, join_tournament_by_code, start_draft_tournament, RLS tournament read
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(12);

DELETE FROM public.tournament_bans
WHERE tournament_id IN (SELECT id FROM public.tournaments WHERE name LIKE 'tier_a_ljs_%');
DELETE FROM public.daily_submissions
WHERE user_id IN (
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1'::uuid,
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2'::uuid,
  'cccccccc-cccc-cccc-cccc-ccccccccccc3'::uuid
);
DELETE FROM public.tournament_scores
WHERE tournament_id IN (SELECT id FROM public.tournaments WHERE name LIKE 'tier_a_ljs_%');
DELETE FROM public.tournament_participants
WHERE tournament_id IN (SELECT id FROM public.tournaments WHERE name LIKE 'tier_a_ljs_%');
DELETE FROM public.tournaments WHERE name LIKE 'tier_a_ljs_%';
DELETE FROM public.users WHERE id IN (
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1'::uuid,
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2'::uuid,
  'cccccccc-cccc-cccc-cccc-ccccccccccc3'::uuid
);
DELETE FROM auth.users WHERE id IN (
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1'::uuid,
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2'::uuid,
  'cccccccc-cccc-cccc-cccc-ccccccccccc3'::uuid
);

INSERT INTO auth.users (id, email, aud, role, created_at, updated_at, is_sso_user, email_confirmed_at)
VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1'::uuid, 'tier_a_ljs_a@test.invalid', 'authenticated', 'authenticated', now(), now(), false, now()),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2'::uuid, 'tier_a_ljs_b@test.invalid', 'authenticated', 'authenticated', now(), now(), false, now()),
  ('cccccccc-cccc-cccc-cccc-ccccccccccc3'::uuid, 'tier_a_ljs_c@test.invalid', 'authenticated', 'authenticated', now(), now(), false, now());

INSERT INTO public.users (id, display_name)
VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1'::uuid, 'TierA Ljs A'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2'::uuid, 'TierA Ljs B'),
  ('cccccccc-cccc-cccc-cccc-ccccccccccc3'::uuid, 'TierA Ljs C')
ON CONFLICT (id) DO NOTHING;

-- Narrow limits for faster setup (participants default restored after limit block)
UPDATE public.app_config
SET max_tournaments_per_user = 2
WHERE key = 'default';

-- ---------- get_tournament_limit_info ----------
SELECT set_config('request.jwt.claim.sub', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1', true);
SET LOCAL ROLE authenticated;

SELECT lives_ok(
  $$SELECT public.create_tournament_draft('tier_a_ljs_d1', '2025-06-01'::date, '2025-06-10'::date)$$,
  'first draft tournament created'
);

SELECT lives_ok(
  $$SELECT public.create_tournament_draft('tier_a_ljs_d2', '2025-06-01'::date, '2025-06-10'::date)$$,
  'second draft tournament created'
);

SELECT results_eq(
  $$SELECT current_count, max_limit FROM public.get_tournament_limit_info()$$,
  $$VALUES (2, 2)$$,
  'get_tournament_limit_info reflects two active/draft participations at cap'
);

SELECT throws_matching(
  $$SELECT public.create_tournament_draft('tier_a_ljs_d3', '2025-06-01'::date, '2025-06-10'::date)$$,
  'maximum number of tournaments',
  'third create_tournament_draft blocked at limit'
);

RESET ROLE;

DELETE FROM public.tournament_participants
WHERE tournament_id IN (SELECT id FROM public.tournaments WHERE name IN ('tier_a_ljs_d1', 'tier_a_ljs_d2'));
DELETE FROM public.tournaments WHERE name IN ('tier_a_ljs_d1', 'tier_a_ljs_d2');

UPDATE public.app_config
SET max_tournaments_per_user = 5,
    max_participants_per_tournament = 15
WHERE key = 'default';

-- ---------- join_tournament_by_code ----------
INSERT INTO public.tournaments (id, name, join_code, start_date, end_date, status, created_by)
VALUES (
  'e0000001-0001-0001-0001-000000000001'::uuid,
  'tier_a_ljs_join',
  'JOINCODE',
  '2025-07-01',
  '2025-07-31',
  'draft',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1'::uuid
);
INSERT INTO public.tournament_participants (tournament_id, user_id)
VALUES ('e0000001-0001-0001-0001-000000000001'::uuid, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1'::uuid);

SELECT set_config('request.jwt.claim.sub', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2', true);
SET LOCAL ROLE authenticated;

SELECT lives_ok(
  $$SELECT public.join_tournament_by_code('joincode')$$,
  'join succeeds with case-insensitive code'
);

SELECT throws_matching(
  $$SELECT public.join_tournament_by_code('joincode')$$,
  'already in this tournament',
  'duplicate join rejected'
);

RESET ROLE;

SELECT set_config('request.jwt.claim.sub', 'cccccccc-cccc-cccc-cccc-ccccccccccc3', true);
SET LOCAL ROLE authenticated;

SELECT throws_matching(
  $$SELECT public.join_tournament_by_code('nosuchcode')$$,
  'Invalid or inactive join code',
  'invalid join code rejected'
);

RESET ROLE;

UPDATE public.app_config
SET max_participants_per_tournament = 2
WHERE key = 'default';

-- Full tournament (max 2 participants): add second participant then c cannot join
INSERT INTO public.tournaments (id, name, join_code, start_date, end_date, status, created_by)
VALUES (
  'e0000002-0002-0002-0002-000000000002'::uuid,
  'tier_a_ljs_full',
  'FULLJOIN',
  '2025-08-01',
  '2025-08-31',
  'draft',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1'::uuid
);
INSERT INTO public.tournament_participants (tournament_id, user_id)
VALUES
  ('e0000002-0002-0002-0002-000000000002'::uuid, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1'::uuid),
  ('e0000002-0002-0002-0002-000000000002'::uuid, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2'::uuid);

SELECT set_config('request.jwt.claim.sub', 'cccccccc-cccc-cccc-cccc-ccccccccccc3', true);
SET LOCAL ROLE authenticated;

SELECT throws_matching(
  $$SELECT public.join_tournament_by_code('fulljoin')$$,
  'full',
  'join rejected when tournament is full'
);

RESET ROLE;

UPDATE public.app_config
SET max_participants_per_tournament = 15
WHERE key = 'default';

-- Banned user cannot rejoin
INSERT INTO public.tournaments (id, name, join_code, start_date, end_date, status, created_by)
VALUES (
  'e0000003-0003-0003-0003-000000000003'::uuid,
  'tier_a_ljs_ban',
  'BANJOIN1',
  '2025-09-01',
  '2025-09-30',
  'draft',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1'::uuid
);
INSERT INTO public.tournament_participants (tournament_id, user_id)
VALUES ('e0000003-0003-0003-0003-000000000003'::uuid, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1'::uuid);

INSERT INTO public.tournament_bans (tournament_id, user_id)
VALUES ('e0000003-0003-0003-0003-000000000003'::uuid, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2'::uuid);

SELECT set_config('request.jwt.claim.sub', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2', true);
SET LOCAL ROLE authenticated;

SELECT throws_matching(
  $$SELECT public.join_tournament_by_code('banjoin1')$$,
  'kicked from this tournament',
  'banned user cannot join'
);

RESET ROLE;

-- ---------- start_draft_tournament ----------
INSERT INTO public.tournaments (id, name, join_code, start_date, end_date, status, created_by)
VALUES (
  'e0000004-0004-0004-0004-000000000004'::uuid,
  'tier_a_ljs_start1',
  'STSTART1',
  '2025-10-01',
  '2025-10-31',
  'draft',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1'::uuid
);
INSERT INTO public.tournament_participants (tournament_id, user_id)
VALUES ('e0000004-0004-0004-0004-000000000004'::uuid, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1'::uuid);

SELECT set_config('request.jwt.claim.sub', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1', true);
SET LOCAL ROLE authenticated;

SELECT throws_matching(
  $$SELECT public.start_draft_tournament('e0000004-0004-0004-0004-000000000004'::uuid)$$,
  'NOT_ENOUGH_PLAYERS',
  'start with only creator fails'
);

RESET ROLE;

INSERT INTO public.tournament_participants (tournament_id, user_id)
VALUES ('e0000004-0004-0004-0004-000000000004'::uuid, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2'::uuid);

SELECT set_config('request.jwt.claim.sub', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1', true);
SET LOCAL ROLE authenticated;

SELECT lives_ok(
  $$SELECT public.start_draft_tournament('e0000004-0004-0004-0004-000000000004'::uuid)$$,
  'start succeeds with two participants'
);

RESET ROLE;

-- ---------- RLS: non-participant cannot read tournament row ----------
INSERT INTO public.tournaments (id, name, join_code, start_date, end_date, status, created_by)
VALUES (
  'e0000005-0005-0005-0005-000000000005'::uuid,
  'tier_a_ljs_rls',
  'RLSJOIN1',
  '2025-11-01',
  '2025-11-30',
  'active',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1'::uuid
);
INSERT INTO public.tournament_participants (tournament_id, user_id)
VALUES ('e0000005-0005-0005-0005-000000000005'::uuid, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1'::uuid);

SELECT set_config('request.jwt.claim.sub', 'cccccccc-cccc-cccc-cccc-ccccccccccc3', true);
SET LOCAL ROLE authenticated;

SELECT is(
  (SELECT count(*)::integer FROM public.tournaments WHERE id = 'e0000005-0005-0005-0005-000000000005'::uuid),
  0,
  'non-participant sees zero tournament rows via RLS'
);

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
