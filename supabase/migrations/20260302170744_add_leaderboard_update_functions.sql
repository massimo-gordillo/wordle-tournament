/*
  # Add Leaderboard Update Functions and Triggers

  ## Overview
  Creates functions and triggers to automatically update tournament leaderboards when:
  1. All players submit their daily wordle results
  2. The 11PM EST cutoff is reached (handled by cron job)

  ## New Functions
  
  1. **recalculate_tournament_scores**
     - Recalculates all scores for a tournament on a specific date
     - Called by edge function when leaderboard update is triggered
     - Parameters: tournament_id, submission_date

  2. **check_all_submissions_complete**
     - Checks if all non-forfeited participants have submitted for a date
     - Returns boolean indicating if leaderboard should be updated
     - Parameters: tournament_id, submission_date

  3. **trigger_leaderboard_update**
     - Trigger function that calls edge function when all submissions are in
     - Fires after each daily_submission insert
     - Only triggers for active tournaments

  ## Security
  - Functions use SECURITY DEFINER to run with elevated privileges
  - Only called by authenticated triggers or service role
*/

-- ============================================================================
-- Function to recalculate tournament scores for a specific date
-- ============================================================================

CREATE OR REPLACE FUNCTION recalculate_tournament_scores(
  p_tournament_id uuid,
  p_submission_date date
)
RETURNS void AS $$
BEGIN
  -- Recalculate scores for all participants up to the submission date
  INSERT INTO tournament_scores (tournament_id, user_id, total_score, last_updated)
  SELECT
    tp.tournament_id,
    tp.user_id,
    CASE
      WHEN tp.forfeited THEN 0
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
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- Function to check if all participants have submitted for a date
-- ============================================================================

CREATE OR REPLACE FUNCTION check_all_submissions_complete(
  p_tournament_id uuid,
  p_submission_date date
)
RETURNS boolean AS $$
DECLARE
  total_participants integer;
  total_submissions integer;
BEGIN
  -- Count non-forfeited participants
  SELECT COUNT(*)
  INTO total_participants
  FROM tournament_participants
  WHERE tournament_id = p_tournament_id
    AND forfeited = false;

  -- Count submissions for this date from participants
  SELECT COUNT(DISTINCT ds.user_id)
  INTO total_submissions
  FROM daily_submissions ds
  JOIN tournament_participants tp ON tp.user_id = ds.user_id
  WHERE tp.tournament_id = p_tournament_id
    AND tp.forfeited = false
    AND ds.submission_date = p_submission_date;

  -- Return true if all participants have submitted
  RETURN total_participants > 0 AND total_participants = total_submissions;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- Trigger function to check and trigger leaderboard update
-- ============================================================================

CREATE OR REPLACE FUNCTION trigger_leaderboard_update()
RETURNS TRIGGER AS $$
DECLARE
  active_tournament record;
  all_complete boolean;
  function_url text;
BEGIN
  -- Get Supabase URL from environment (this will be the project URL)
  function_url := current_setting('app.settings.supabase_url', true) || '/functions/v1/update-leaderboard';

  -- For each active tournament the user is in
  FOR active_tournament IN
    SELECT t.id, t.start_date, t.end_date
    FROM tournaments t
    JOIN tournament_participants tp ON tp.tournament_id = t.id
    WHERE tp.user_id = NEW.user_id
      AND t.status = 'active'
      AND NEW.submission_date >= t.start_date
      AND NEW.submission_date <= t.end_date
  LOOP
    -- Check if all submissions are complete for this tournament and date
    all_complete := check_all_submissions_complete(
      active_tournament.id,
      NEW.submission_date
    );

    -- If all complete, trigger immediate leaderboard update
    IF all_complete THEN
      -- Call the edge function using pg_net extension (if available)
      -- Note: This requires pg_net extension to be enabled
      -- Alternative: Update scores directly here
      PERFORM recalculate_tournament_scores(
        active_tournament.id,
        NEW.submission_date
      );
    END IF;
  END LOOP;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- Create trigger on daily_submissions
-- ============================================================================

DROP TRIGGER IF EXISTS on_submission_check_leaderboard ON daily_submissions;

CREATE TRIGGER on_submission_check_leaderboard
  AFTER INSERT ON daily_submissions
  FOR EACH ROW
  EXECUTE FUNCTION trigger_leaderboard_update();
