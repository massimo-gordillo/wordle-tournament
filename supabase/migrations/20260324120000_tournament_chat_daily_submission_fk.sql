/*
  Link tournament_chat result rows to daily_submissions for canonical grid + score.
*/

ALTER TABLE tournament_chat
  ADD COLUMN IF NOT EXISTS daily_submission_id uuid REFERENCES daily_submissions(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_tournament_chat_daily_submission_id
  ON tournament_chat(daily_submission_id)
  WHERE daily_submission_id IS NOT NULL;

UPDATE tournament_chat tc
SET daily_submission_id = ds.id
FROM daily_submissions ds
WHERE tc.message_type = 'result'
  AND tc.daily_submission_id IS NULL
  AND ds.user_id = tc.user_id
  AND ds.submission_date = tc.submission_date;
