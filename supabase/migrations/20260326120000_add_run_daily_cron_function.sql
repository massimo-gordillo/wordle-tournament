/*
  # Add run_daily_cron() helper

  This wraps the daily cron SQL from CRON_JOB_LOGIC.md into a reusable function
  that can be:
  - Invoked manually in local/dev via: SELECT run_daily_cron();
  - Invoked by a scheduler in production (GitHub Actions, EasyCron, pg_cron, etc.)

  Behavior:
  1. Apply -2 point penalties for users who haven't submitted today.
  2. Recalculate all tournament scores (including penalties).
  3. Auto-forfeit users with N consecutive penalty days.
  4. Close tournaments whose end_date is today or earlier.
*/

CREATE OR REPLACE FUNCTION run_daily_cron()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  today_date date;
  v_auto_n integer;
  first_streak_day date;
BEGIN
  -- Get today's date in EST timezone
  today_date := (now() AT TIME ZONE 'America/New_York')::date;

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
  -- STEP 1: Apply penalties for missing submissions
  -- ============================================================================

  -- For each user in an active tournament who hasn't submitted today,
  -- create a penalty submission with -2 points.
  -- IMPORTANT: exclude forfeited participants here; forfeiture penalties are
  -- tournament-scoped and handled in recalculate_tournament_scores.
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
    -- Tournament is active
    t.status = 'active'
    -- Today is within tournament date range
    AND today_date >= t.start_date
    AND today_date <= t.end_date
    -- User has not forfeited this tournament
    AND tp.forfeited = false
    -- User has not submitted today
    AND NOT EXISTS (
      SELECT 1 FROM daily_submissions ds
      WHERE ds.user_id = tp.user_id
        AND ds.submission_date = today_date
    )
  ON CONFLICT (user_id, submission_date) DO NOTHING;

  -- ============================================================================
  -- STEP 2: Recalculate all tournament scores for active/closed tournaments
  -- ============================================================================

  INSERT INTO tournament_scores (tournament_id, user_id, total_score, last_updated)
  SELECT
    tp.tournament_id,
    tp.user_id,
    -- Sum all daily scores within tournament date range (including -2 penalties)
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
  -- STEP 2b: Auto-forfeit users with N consecutive penalty days
  -- ============================================================================

  WITH eligible_forfeit AS (
    SELECT
      tp.tournament_id,
      tp.user_id
    FROM tournament_participants tp
    JOIN tournaments t ON t.id = tp.tournament_id
    WHERE
      t.status = 'active'
      AND tp.forfeited = false
      -- Tournament started on or after the first day of this streak window
      AND t.start_date >= first_streak_day
      -- User has a penalty submission on every day in the streak window
      AND (
        SELECT COUNT(DISTINCT ds.submission_date)
        FROM daily_submissions ds
        WHERE ds.user_id = tp.user_id
          AND ds.submission_text = 'NO SUBMISSION - PENALTY'
          AND ds.submission_date BETWEEN first_streak_day AND today_date
      ) >= v_auto_n
  )
  PERFORM forfeit_tournament_internal(tournament_id, user_id)
  FROM eligible_forfeit;

  -- ============================================================================
  -- STEP 3: Close tournaments that have reached (or passed) their end date
  -- ============================================================================

  UPDATE tournaments
  SET status = 'closed'
  WHERE status = 'active'
    AND end_date <= today_date;

END;
$$;

GRANT EXECUTE ON FUNCTION run_daily_cron() TO authenticated;

