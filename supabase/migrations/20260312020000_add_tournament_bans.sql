/*
  # Tournament bans

  - Adds tournament_bans table to permanently record users removed from a tournament.
  - Updates join_tournament_by_code to prevent banned users from re-joining.
*/

CREATE TABLE IF NOT EXISTS tournament_bans (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  tournament_id uuid NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tournament_id, user_id)
);

-- No RLS needed: only server-side functions read this table via SECURITY DEFINER.

CREATE OR REPLACE FUNCTION join_tournament_by_code(p_join_code text)
RETURNS uuid AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_tournament_id uuid;
  v_active_count integer;
  v_participant_count integer;
  v_max_tournaments integer;
  v_max_participants integer;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT
    max_tournaments_per_user,
    max_participants_per_tournament
  INTO
    v_max_tournaments,
    v_max_participants
  FROM app_config
  ORDER BY updated_at DESC
  LIMIT 1;

  IF v_max_tournaments IS NULL THEN
    v_max_tournaments := 5;
  END IF;

  IF v_max_participants IS NULL THEN
    v_max_participants := 10;
  END IF;

  SELECT id
  INTO v_tournament_id
  FROM tournaments
  WHERE upper(join_code) = upper(p_join_code)
    AND status IN ('draft', 'active')
  LIMIT 1;

  IF v_tournament_id IS NULL THEN
    RAISE EXCEPTION 'Invalid or inactive join code';
  END IF;

  -- Prevent banned users from re-joining this tournament
  IF EXISTS (
    SELECT 1
    FROM tournament_bans b
    WHERE b.tournament_id = v_tournament_id
      AND b.user_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'You have been kicked from this tournament';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM tournament_participants tp
    WHERE tp.tournament_id = v_tournament_id
      AND tp.user_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'You are already in this tournament';
  END IF;

  -- Exclude forfeited participations from count
  SELECT COUNT(*)
  INTO v_active_count
  FROM tournament_participants tp
  JOIN tournaments t ON t.id = tp.tournament_id
  WHERE tp.user_id = v_user_id
    AND t.status IN ('draft', 'active')
    AND (tp.forfeited IS NOT TRUE);

  IF v_active_count >= v_max_tournaments THEN
    RAISE EXCEPTION 'You are already in the maximum number of tournaments (%s)', v_max_tournaments;
  END IF;

  SELECT COUNT(*)
  INTO v_participant_count
  FROM tournament_participants tp
  WHERE tp.tournament_id = v_tournament_id;

  IF v_participant_count >= v_max_participants THEN
    RAISE EXCEPTION 'This tournament is full (%s players max)', v_max_participants;
  END IF;

  INSERT INTO tournament_participants (tournament_id, user_id)
  VALUES (v_tournament_id, v_user_id);

  RETURN v_tournament_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

REVOKE ALL ON FUNCTION join_tournament_by_code(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION join_tournament_by_code(text) TO authenticated;

