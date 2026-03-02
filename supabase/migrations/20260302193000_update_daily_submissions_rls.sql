/*
  # Tighten daily_submissions RLS

  Previous policy allowed all authenticated users to read all submissions.

  This migration:
  - Removes the broad "Users can read all submissions" policy
  - Adds policies so that:
      - Users can always read their own submissions
      - Users can read submissions of players who share any tournament with them
        (no recursion back into daily_submissions)
*/

-- Drop overly-permissive SELECT policy
DROP POLICY IF EXISTS "Users can read all submissions" ON daily_submissions;

-- Users can read their own submissions
CREATE POLICY "Users can read their own submissions"
  ON daily_submissions
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

-- Users can read submissions from players who share a tournament with them
CREATE POLICY "Users can read submissions from shared tournaments"
  ON daily_submissions
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM tournament_participants tp_self
      JOIN tournament_participants tp_other
        ON tp_self.tournament_id = tp_other.tournament_id
      WHERE tp_self.user_id = auth.uid()
        AND tp_other.user_id = daily_submissions.user_id
    )
  );

