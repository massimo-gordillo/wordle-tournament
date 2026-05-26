-- pgTAP: anonymize_my_account (forfeit active, cancel/leave drafts, scrub PII)
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(10);

DELETE FROM public.tournament_chat
WHERE tournament_id IN (SELECT id FROM public.tournaments WHERE name LIKE 'tier_a_del_%');
DELETE FROM public.tournament_bans
WHERE tournament_id IN (SELECT id FROM public.tournaments WHERE name LIKE 'tier_a_del_%');
DELETE FROM public.daily_submissions
WHERE user_id IN (
  'f1111111-1111-1111-1111-111111111111'::uuid,
  'f2222222-2222-2222-2222-222222222222'::uuid
);
DELETE FROM public.tournament_scores
WHERE tournament_id IN (SELECT id FROM public.tournaments WHERE name LIKE 'tier_a_del_%');
DELETE FROM public.tournament_participants
WHERE tournament_id IN (SELECT id FROM public.tournaments WHERE name LIKE 'tier_a_del_%');
DELETE FROM public.tournaments WHERE name LIKE 'tier_a_del_%';
DELETE FROM public.users WHERE id IN (
  'f1111111-1111-1111-1111-111111111111'::uuid,
  'f2222222-2222-2222-2222-222222222222'::uuid
);
DELETE FROM auth.users WHERE id IN (
  'f1111111-1111-1111-1111-111111111111'::uuid,
  'f2222222-2222-2222-2222-222222222222'::uuid
);

INSERT INTO auth.users (id, email, aud, role, created_at, updated_at, is_sso_user, email_confirmed_at)
VALUES
  ('f1111111-1111-1111-1111-111111111111'::uuid, 'tier_a_del_a@test.invalid', 'authenticated', 'authenticated', now(), now(), false, now()),
  ('f2222222-2222-2222-2222-222222222222'::uuid, 'tier_a_del_b@test.invalid', 'authenticated', 'authenticated', now(), now(), false, now());

INSERT INTO public.users (id, display_name)
VALUES
  ('f1111111-1111-1111-1111-111111111111'::uuid, 'TierA Del A'),
  ('f2222222-2222-2222-2222-222222222222'::uuid, 'TierA Del B')
ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name, deleted_at = NULL;

-- ---------- draft creator: cancel ----------
SELECT set_config('request.jwt.claim.sub', 'f1111111-1111-1111-1111-111111111111', true);
SET LOCAL ROLE authenticated;

SELECT lives_ok(
  $$SELECT public.create_tournament_draft('tier_a_del_draft_cancel', '2026-06-01'::date, '2026-06-10'::date)$$,
  'draft created for cancel test'
);

SELECT lives_ok(
  $$SELECT public.anonymize_my_account()$$,
  'anonymize_my_account runs for draft creator'
);

RESET ROLE;

SELECT results_eq(
  $$SELECT status FROM public.tournaments WHERE name = 'tier_a_del_draft_cancel'$$,
  $$VALUES ('cancelled'::text)$$,
  'creator draft tournament cancelled'
);

SELECT results_eq(
  $$SELECT display_name, deleted_at IS NOT NULL FROM public.users WHERE id = 'f1111111-1111-1111-1111-111111111111'::uuid$$,
  $$VALUES ('Deleted User'::text, true)$$,
  'creator profile anonymized after draft cancel'
);

UPDATE public.users
SET display_name = 'TierA Del A', deleted_at = NULL
WHERE id = 'f1111111-1111-1111-1111-111111111111'::uuid;

DELETE FROM public.tournament_participants
WHERE tournament_id IN (SELECT id FROM public.tournaments WHERE name = 'tier_a_del_draft_cancel');
DELETE FROM public.tournaments WHERE name = 'tier_a_del_draft_cancel';

-- ---------- draft joiner: leave ----------
INSERT INTO public.tournaments (id, name, join_code, start_date, end_date, status, created_by)
VALUES (
  'f0000001-0001-0001-0001-000000000001'::uuid,
  'tier_a_del_draft_leave',
  'DELLEAVE',
  '2026-07-01',
  '2026-07-10',
  'draft',
  'f2222222-2222-2222-2222-222222222222'::uuid
);
INSERT INTO public.tournament_participants (tournament_id, user_id)
VALUES
  ('f0000001-0001-0001-0001-000000000001'::uuid, 'f2222222-2222-2222-2222-222222222222'::uuid),
  ('f0000001-0001-0001-0001-000000000001'::uuid, 'f1111111-1111-1111-1111-111111111111'::uuid);

SELECT set_config('request.jwt.claim.sub', 'f1111111-1111-1111-1111-111111111111', true);
SET LOCAL ROLE authenticated;

SELECT lives_ok(
  $$SELECT public.anonymize_my_account()$$,
  'anonymize_my_account runs for draft joiner'
);

RESET ROLE;

SELECT is_empty(
  $$SELECT 1 FROM public.tournament_participants
    WHERE tournament_id = 'f0000001-0001-0001-0001-000000000001'::uuid
      AND user_id = 'f1111111-1111-1111-1111-111111111111'::uuid$$,
  'joiner removed from draft tournament'
);

UPDATE public.users
SET display_name = 'TierA Del A', deleted_at = NULL
WHERE id = 'f1111111-1111-1111-1111-111111111111'::uuid;

DELETE FROM public.tournament_participants
WHERE tournament_id = 'f0000001-0001-0001-0001-000000000001'::uuid;
DELETE FROM public.tournaments WHERE id = 'f0000001-0001-0001-0001-000000000001'::uuid;

-- ---------- active: forfeit ----------
SELECT set_config('request.jwt.claim.sub', 'f1111111-1111-1111-1111-111111111111', true);
SET LOCAL ROLE authenticated;

SELECT lives_ok(
  $$SELECT public.create_tournament_draft('tier_a_del_active', '2026-06-01'::date, '2026-06-05'::date)$$,
  'draft created for active forfeit test'
);

RESET ROLE;

INSERT INTO public.tournament_participants (tournament_id, user_id)
SELECT id, 'f2222222-2222-2222-2222-222222222222'::uuid
FROM public.tournaments
WHERE name = 'tier_a_del_active'
ON CONFLICT DO NOTHING;

SELECT set_config('request.jwt.claim.sub', 'f1111111-1111-1111-1111-111111111111', true);
SET LOCAL ROLE authenticated;

SELECT lives_ok(
  $$SELECT public.start_draft_tournament(
    (SELECT id FROM public.tournaments WHERE name = 'tier_a_del_active')
  )$$,
  'active tournament started'
);

SELECT lives_ok(
  $$SELECT public.anonymize_my_account()$$,
  'anonymize_my_account runs for active participant'
);

RESET ROLE;

SELECT results_eq(
  $$SELECT forfeited FROM public.tournament_participants tp
    JOIN public.tournaments t ON t.id = tp.tournament_id
    WHERE t.name = 'tier_a_del_active'
      AND tp.user_id = 'f1111111-1111-1111-1111-111111111111'::uuid$$,
  $$VALUES (true)$$,
  'active tournament participation forfeited on delete'
);

SELECT * FROM finish();
ROLLBACK;
