/*
  # Enforce daily submission cutoff at the database level

  Business rule:
  - Users can only submit for "today" (EST) until cutoff_hour_est (default 23 = 11 PM).
  - After the cutoff, normal submissions for today must be rejected.
  - System/cron penalties ("NO SUBMISSION - PENALTY") must still be allowed after cutoff.

  This keeps the client logic honest and ensures that even if a request arrives
  after the cutoff, the insert fails rather than silently overwriting the
  penalty row or creating inconsistent state.
*/

CREATE OR REPLACE FUNCTION enforce_daily_submission_cutoff()
RETURNS trigger AS $$
DECLARE
  v_est_now        timestamptz;
  v_today          date;
  v_cutoff_hour    integer;
  v_current_hour   integer;
BEGIN
  -- Current time in America/New_York
  v_est_now := (now() AT TIME ZONE 'America/New_York');
  v_today := v_est_now::date;
  v_current_hour := EXTRACT(HOUR FROM v_est_now);

  -- Load cutoff hour from app_config (fallback to 23 if missing)
  SELECT cutoff_hour_est
  INTO v_cutoff_hour
  FROM app_config
  ORDER BY updated_at DESC
  LIMIT 1;

  IF v_cutoff_hour IS NULL THEN
    v_cutoff_hour := 23;
  END IF;

  -- Block normal user submissions for "today" once cutoff has passed.
  -- Allow system/cron penalty rows which always use the fixed label
  -- 'NO SUBMISSION - PENALTY'.
  IF NEW.submission_date = v_today
     AND v_current_hour >= v_cutoff_hour
     AND NEW.submission_text <> 'NO SUBMISSION - PENALTY' THEN
    RAISE EXCEPTION 'SUBMISSION_CUTOFF_PASSED'
      USING ERRCODE = 'P0001',
            MESSAGE = 'Submission window for today has closed.';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public;

-- Ensure the trigger exists and uses the latest function definition
DROP TRIGGER IF EXISTS enforce_daily_submission_cutoff ON daily_submissions;

CREATE TRIGGER enforce_daily_submission_cutoff
  BEFORE INSERT ON daily_submissions
  FOR EACH ROW
  EXECUTE FUNCTION enforce_daily_submission_cutoff();

