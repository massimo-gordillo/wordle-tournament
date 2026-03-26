/*
  # Add date-driven cron helpers (applies after 20260326120000)

  Why this migration exists:
  - 20260326120000_add_run_daily_cron_function.sql was already applied locally.
  - We now want a more flexible interface for local/dev without editing already-applied migrations.

  Adds:
  - run_daily_cron_for_date(p_run_date date): run cron logic for a specific EST Wordle day.
  - run_daily_cron(): redefined as thin wrapper that calls run_daily_cron_for_date(today_est).
  - run_daily_cron_for_active_tournaments_range(p_max_date date): tournament-driven catch-up.
*/

CREATE OR REPLACE FUNCTION run_daily_cron_for_date(p_run_date date)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  today_date date := p_run_date;
  v_auto_n integer;
  first_streak_day date;
  v_eligible record;
BEGIN
  -- Load auto-forfeit config: number of consecutive penalty days before auto-forfeit
  SELECT auto_forfeit_consecutive_penalties
  INTO v_auto_n
  FROM app_config
  ORDER BY updated_at DESC
  LIMIT 1;

  IF v_auto_n IS NULL OR v_auto_n < 1 THEN
    v_auto_n := 3;
  END IF;

  -- First day of the streak window we care about (last N days including today)
  first_streak_day := today_date - (v_auto_n - 1);

  -- ============================================================================
  -- STEP 1: Apply penalties for missing submissions (for today_date)
  -- ============================================================================
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

  -- ============================================================================
  -- STEP 2: Recalculate tournament scores up to today_date
  -- ============================================================================
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

  -- ============================================================================
  -- STEP 2b: Auto-forfeit users with N consecutive penalty days ending today_date
  -- ============================================================================
  FOR v_eligible IN
    SELECT
      tp.tournament_id,
      tp.user_id
    FROM tournament_participants tp
    JOIN tournaments t ON t.id = tp.tournament_id
    WHERE
      t.status = 'active'
      AND tp.forfeited = false
      AND t.start_date >= first_streak_day
      AND (
        SELECT COUNT(DISTINCT ds.submission_date)
        FROM daily_submissions ds
        WHERE ds.user_id = tp.user_id
          AND ds.submission_text = 'NO SUBMISSION - PENALTY'
          AND ds.submission_date BETWEEN first_streak_day AND today_date
      ) >= v_auto_n
  LOOP
    PERFORM forfeit_tournament_internal(v_eligible.tournament_id, v_eligible.user_id);
  END LOOP;

  -- ============================================================================
  -- STEP 3: Close tournaments that have reached (or passed) their end date
  -- ============================================================================
  UPDATE tournaments
  SET status = 'closed'
  WHERE status = 'active'
    AND end_date <= today_date;
END;
$$;

GRANT EXECUTE ON FUNCTION run_daily_cron_for_date(date) TO authenticated;

-- Redefine run_daily_cron() as a wrapper that targets today's EST day.
CREATE OR REPLACE FUNCTION run_daily_cron()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today_est date;
BEGIN
  v_today_est := (now() AT TIME ZONE 'America/New_York')::date;
  PERFORM run_daily_cron_for_date(v_today_est);
END;
$$;

GRANT EXECUTE ON FUNCTION run_daily_cron() TO authenticated;

-- Tournament-driven helper: run daily cron for each day covered by any active tournament.
-- Useful for local/dev catch-up without touching "today" before cutoff.
CREATE OR REPLACE FUNCTION run_daily_cron_for_active_tournaments_range(p_max_date date)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_start date;
  v_end   date;
  v_day   date;
BEGIN
  SELECT MIN(start_date), MAX(end_date)
  INTO v_start, v_end
  FROM tournaments
  WHERE status = 'active';

  IF v_start IS NULL OR v_end IS NULL THEN
    RETURN;
  END IF;

  IF v_end > p_max_date THEN
    v_end := p_max_date;
  END IF;

  IF v_start > v_end THEN
    RETURN;
  END IF;

  v_day := v_start;
  WHILE v_day <= v_end LOOP
    PERFORM run_daily_cron_for_date(v_day);
    v_day := v_day + INTERVAL '1 day';
  END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION run_daily_cron_for_active_tournaments_range(date) TO authenticated;

