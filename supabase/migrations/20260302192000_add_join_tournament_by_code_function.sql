/*
  # Join Tournament by Code (RPC)

  Adds a SECURITY DEFINER function that:
  - Looks up a tournament by join_code (case-insensitive)
  - Enforces:
      - tournament status is draft or active
      - max 4 active/draft tournaments per user
      - max 15 participants per tournament
      - user is not already a participant
  - Inserts the caller as a participant

  This lets the client join via RPC without needing broad SELECT
  access to tournaments or manual INSERTs into tournament_participants.
*/

CREATE OR REPLACE FUNCTION join_tournament_by_code(p_join_code text)
RETURNS uuid AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_tournament_id uuid;
  v_active_count integer;
  v_participant_count integer;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Find tournament by join code (case-insensitive), only draft/active
  SELECT id
  INTO v_tournament_id
  FROM tournaments
  WHERE upper(join_code) = upper(p_join_code)
    AND status IN ('draft', 'active')
  LIMIT 1;

  IF v_tournament_id IS NULL THEN
    RAISE EXCEPTION 'Invalid or inactive join code';
  END IF;

  -- Check user is not already a participant
  IF EXISTS (
    SELECT 1
    FROM tournament_participants tp
    WHERE tp.tournament_id = v_tournament_id
      AND tp.user_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'You are already in this tournament';
  END IF;

  -- Enforce max 4 tournaments per user (draft + active)
  SELECT COUNT(*)
  INTO v_active_count
  FROM tournament_participants tp
  JOIN tournaments t ON t.id = tp.tournament_id
  WHERE tp.user_id = v_user_id
    AND t.status IN ('draft', 'active');

  IF v_active_count >= 4 THEN
    RAISE EXCEPTION 'You are already in the maximum number of tournaments (4)';
  END IF;

  -- Enforce max 15 participants per tournament
  SELECT COUNT(*)
  INTO v_participant_count
  FROM tournament_participants tp
  WHERE tp.tournament_id = v_tournament_id;

  IF v_participant_count >= 15 THEN
    RAISE EXCEPTION 'This tournament is full (15 players max)';
  END IF;

  -- Insert participant row
  INSERT INTO tournament_participants (tournament_id, user_id)
  VALUES (v_tournament_id, v_user_id);

  RETURN v_tournament_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

