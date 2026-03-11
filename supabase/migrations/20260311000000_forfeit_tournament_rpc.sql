/*
  # Forfeit tournament RPC and forfeited score consistency

  - Adds forfeit_tournament(p_tournament_id) RPC that:
    - Rejects if caller is not a participant or has already forfeited (returns error).
    - Sets tournament_participants.forfeited = true and tournament_scores.total_score = -1.
  - Ensures recalculate_tournament_scores uses -1 (not 0) for forfeited participants
    so display and backend stay consistent and forfeited players are not overwritten incorrectly.
*/

-- ============================================================================
-- Use -1 for forfeited in recalculate_tournament_scores
-- ============================================================================

CREATE OR REPLACE FUNCTION recalculate_tournament_scores(
  p_tournament_id uuid,
  p_submission_date date
)
RETURNS void AS $$
BEGIN
  INSERT INTO tournament_scores (tournament_id, user_id, total_score, last_updated)
  SELECT
    tp.tournament_id,
    tp.user_id,
    CASE
      WHEN tp.forfeited THEN -1
      ELSE COALESCE(SUM(ds.wordle_score), 0)
    END as total_score,
    now()
  FROM tournament_participants tp
  JOIN tournaments t ON t.id = tp.tournament_id
  LEFT JOIN daily_submissions ds ON ds.user_id = tp.user_id
    AND ds.submission_date >= t.start_date
    AND ds.submission_date <= p_submission_date
    AND ds.submission_date <= t.end_date
  WHERE tp.tournament_id = p_tournament_id
    AND t.status = 'active'
  GROUP BY tp.tournament_id, tp.user_id, tp.forfeited
  ON CONFLICT (tournament_id, user_id)
  DO UPDATE SET
    total_score = EXCLUDED.total_score,
    last_updated = EXCLUDED.last_updated;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ============================================================================
-- Forfeit tournament RPC: set forfeited and score -1; reject if already forfeited
-- ============================================================================

CREATE OR REPLACE FUNCTION forfeit_tournament(p_tournament_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_updated integer;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'P0001';
  END IF;

  -- Only allow forfeit if user is a participant and not already forfeited
  SELECT COUNT(*) INTO v_updated
  FROM tournament_participants
  WHERE tournament_id = p_tournament_id
    AND user_id = v_uid
    AND forfeited = false;

  IF v_updated = 0 THEN
    RAISE EXCEPTION 'ALREADY_FORFEITED_OR_NOT_PARTICIPANT'
      USING ERRCODE = 'P0001',
            MESSAGE = 'You have already forfeited this tournament or are not a participant.';
  END IF;

  -- Mark as forfeited
  UPDATE tournament_participants
  SET forfeited = true
  WHERE tournament_id = p_tournament_id
    AND user_id = v_uid
    AND forfeited = false;

  -- Set tournament_scores to -1 (upsert so row exists)
  INSERT INTO tournament_scores (tournament_id, user_id, total_score, last_updated)
  VALUES (p_tournament_id, v_uid, -1, now())
  ON CONFLICT (tournament_id, user_id)
  DO UPDATE SET total_score = -1, last_updated = now();
END;
$$;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION forfeit_tournament(uuid) TO authenticated;
