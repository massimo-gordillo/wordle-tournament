-- Auto-forfeit (Step 2b): per tournament, only when the tournament has been running at least N days
-- (inclusive: today_date - start_date >= N - 1) and the user has NO SUBMISSION - PENALTY on each of the
-- last N calendar days ending today_date that fall within [start_date, end_date].

CREATE OR REPLACE FUNCTION public.run_daily_cron_for_date(p_run_date date) RETURNS void
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  today_date date := p_run_date;
  v_auto_n integer;
  v_eligible record;
BEGIN
  SELECT auto_forfeit_consecutive_penalties
  INTO v_auto_n
  FROM app_config
  ORDER BY updated_at DESC
  LIMIT 1;

  IF v_auto_n IS NULL OR v_auto_n < 1 THEN
    v_auto_n := 3;
  END IF;

  INSERT INTO daily_submissions (user_id, submission_date, submission_text, wordle_score, submitted_at)
  SELECT DISTINCT
    tp.user_id,
    today_date,
    'NO SUBMISSION - PENALTY',
    -2,
    now()
  FROM tournament_participants tp
  JOIN tournaments t ON t.id = tp.tournament_id
  WHERE
    t.status = 'active'
    AND today_date >= t.start_date
    AND today_date <= t.end_date
    AND tp.forfeited = false
    AND NOT EXISTS (
      SELECT 1 FROM daily_submissions ds
      WHERE ds.user_id = tp.user_id
        AND ds.submission_date = today_date
    )
  ON CONFLICT (user_id, submission_date) DO NOTHING;

  INSERT INTO tournament_scores (tournament_id, user_id, total_score, last_updated)
  SELECT
    tp.tournament_id,
    tp.user_id,
    COALESCE(SUM(ds.wordle_score), 0) AS total_score,
    now()
  FROM tournament_participants tp
  JOIN tournaments t ON t.id = tp.tournament_id
  LEFT JOIN daily_submissions ds ON ds.user_id = tp.user_id
    AND ds.submission_date >= t.start_date
    AND ds.submission_date <= today_date
    AND ds.submission_date <= t.end_date
  WHERE t.status IN ('active', 'closed')
  GROUP BY tp.tournament_id, tp.user_id, tp.forfeited
  ON CONFLICT (tournament_id, user_id)
  DO UPDATE SET
    total_score = EXCLUDED.total_score,
    last_updated = EXCLUDED.last_updated;

  FOR v_eligible IN
    SELECT
      tp.tournament_id,
      tp.user_id
    FROM tournament_participants tp
    JOIN tournaments t ON t.id = tp.tournament_id
    WHERE
      t.status = 'active'
      AND tp.forfeited = false
      AND (today_date - t.start_date) >= (v_auto_n - 1)
      AND NOT EXISTS (
        SELECT 1
        FROM (
          SELECT generate_series(0, v_auto_n - 1)::integer AS i
        ) streak
        WHERE (today_date - streak.i) >= t.start_date
          AND (today_date - streak.i) <= t.end_date
          AND NOT EXISTS (
            SELECT 1
            FROM daily_submissions ds
            WHERE ds.user_id = tp.user_id
              AND ds.submission_date = today_date - streak.i
              AND ds.submission_text = 'NO SUBMISSION - PENALTY'
          )
      )
  LOOP
    PERFORM forfeit_tournament_internal(v_eligible.tournament_id, v_eligible.user_id);
  END LOOP;

  UPDATE tournaments
  SET status = 'closed'
  WHERE status = 'active'
    AND end_date <= today_date;
END;
$$;
