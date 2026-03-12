/*
  # Kick tournament participant RPC

  Allows a tournament creator to remove a participant from a draft tournament
  and permanently ban them from re-joining that tournament.
*/

CREATE OR REPLACE FUNCTION kick_tournament_participant(
  p_tournament_id uuid,
  p_user_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_created_by uuid;
  v_status text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT created_by, status
  INTO v_created_by, v_status
  FROM tournaments
  WHERE id = p_tournament_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Tournament not found';
  END IF;

  IF v_created_by <> v_uid THEN
    RAISE EXCEPTION 'Only the creator can remove players from this tournament';
  END IF;

  IF v_status <> 'draft' THEN
    RAISE EXCEPTION 'Players can only be removed while the tournament is in draft status';
  END IF;

  -- Record ban so the user cannot re-join, then remove from participants
  INSERT INTO tournament_bans (tournament_id, user_id)
  VALUES (p_tournament_id, p_user_id)
  ON CONFLICT (tournament_id, user_id) DO NOTHING;

  DELETE FROM tournament_participants
  WHERE tournament_id = p_tournament_id
    AND user_id = p_user_id;
END;
$$;

REVOKE ALL ON FUNCTION kick_tournament_participant(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION kick_tournament_participant(uuid, uuid) TO authenticated;

