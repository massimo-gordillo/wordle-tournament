/*
  # Make score update trigger SECURITY DEFINER

  After removing permissive tournament_scores write policies, we must ensure
  the trigger that updates tournament_scores can still run.
*/

CREATE OR REPLACE FUNCTION update_tournament_scores_on_submission()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO tournament_scores (tournament_id, user_id, total_score, last_updated)
  SELECT
    tp.tournament_id,
    NEW.user_id,
    COALESCE(SUM(ds.wordle_score), 0) as total_score,
    now()
  FROM tournament_participants tp
  JOIN tournaments t ON t.id = tp.tournament_id
  LEFT JOIN daily_submissions ds ON ds.user_id = NEW.user_id
    AND ds.submission_date >= t.start_date
    AND ds.submission_date <= t.end_date
  WHERE tp.user_id = NEW.user_id
    AND t.status IN ('active', 'closed')
    AND tp.forfeited = false
    AND NEW.submission_date >= t.start_date
    AND NEW.submission_date <= t.end_date
  GROUP BY tp.tournament_id, NEW.user_id
  ON CONFLICT (tournament_id, user_id)
  DO UPDATE SET
    total_score = EXCLUDED.total_score,
    last_updated = EXCLUDED.last_updated;

  RETURN NEW;
END;
$$;

