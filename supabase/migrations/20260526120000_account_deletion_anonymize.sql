-- Account deletion: keep public.users tombstone, anonymize PII, forfeit/cancel/leave tournaments.

ALTER TABLE public.users
  DROP CONSTRAINT IF EXISTS users_id_fkey;

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS deleted_at timestamptz;

CREATE OR REPLACE FUNCTION public.anonymize_my_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_rec record;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.users WHERE id = v_uid AND deleted_at IS NOT NULL
  ) THEN
    RETURN;
  END IF;

  -- Step A: forfeit active tournaments
  FOR v_rec IN
    SELECT tp.tournament_id
    FROM public.tournament_participants tp
    JOIN public.tournaments t ON t.id = tp.tournament_id
    WHERE tp.user_id = v_uid
      AND tp.forfeited = false
      AND t.status = 'active'
    ORDER BY tp.tournament_id
  LOOP
    PERFORM public.forfeit_tournament_internal(v_rec.tournament_id, v_uid);
  END LOOP;

  -- Step B: cancel draft tournaments created by user
  FOR v_rec IN
    SELECT id AS tournament_id
    FROM public.tournaments
    WHERE created_by = v_uid
      AND status = 'draft'
    ORDER BY id
  LOOP
    PERFORM public.cancel_tournament_draft(v_rec.tournament_id);
  END LOOP;

  -- Step B: leave draft tournaments joined (not creator)
  FOR v_rec IN
    SELECT t.id AS tournament_id
    FROM public.tournaments t
    INNER JOIN public.tournament_participants tp
      ON tp.tournament_id = t.id AND tp.user_id = v_uid
    WHERE t.status = 'draft'
      AND t.created_by <> v_uid
    ORDER BY t.id
  LOOP
    PERFORM public.leave_draft_tournament(v_rec.tournament_id);
  END LOOP;

  -- Step C: anonymize PII
  UPDATE public.users
  SET display_name = 'Deleted User',
      deleted_at = now()
  WHERE id = v_uid;

  UPDATE public.daily_submissions
  SET submission_text = '[deleted]'
  WHERE user_id = v_uid;

  UPDATE public.tournament_chat
  SET message = '[deleted]'
  WHERE user_id = v_uid;
END;
$$;

ALTER FUNCTION public.anonymize_my_account() OWNER TO postgres;

REVOKE ALL ON FUNCTION public.anonymize_my_account() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.anonymize_my_account() TO authenticated;
GRANT EXECUTE ON FUNCTION public.anonymize_my_account() TO service_role;
