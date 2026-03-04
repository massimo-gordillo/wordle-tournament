/*
  # Rewrite RLS using helper functions

  Goals:
  - Remove overly-permissive policies
  - Avoid self-referential RLS recursion
  - Require RPC for joining tournaments (join-by-code)
  - Prevent clients from writing tournament_scores directly
*/

-- ============================
-- TOURNAMENTS
-- ============================

DROP POLICY IF EXISTS "Users can create tournaments they own" ON tournaments;
DROP POLICY IF EXISTS "Creators can read their tournaments" ON tournaments;
DROP POLICY IF EXISTS "Participants can read joined tournaments" ON tournaments;
DROP POLICY IF EXISTS "Creators can update their tournaments" ON tournaments;
DROP POLICY IF EXISTS "Creators can delete draft tournaments" ON tournaments;
DROP POLICY IF EXISTS "Users can create their own tournaments" ON tournaments;
DROP POLICY IF EXISTS "Users can create tournaments" ON tournaments;
DROP POLICY IF EXISTS "Tournament creators can read their tournaments" ON tournaments;
DROP POLICY IF EXISTS "Tournament participants can read tournaments they joined" ON tournaments;

CREATE POLICY "Users can create tournaments they own"
  ON tournaments
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = created_by);

CREATE POLICY "Users can read accessible tournaments"
  ON tournaments
  FOR SELECT
  TO authenticated
  USING (can_access_tournament(id, auth.uid()));

CREATE POLICY "Creators can update their tournaments"
  ON tournaments
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = created_by)
  WITH CHECK (auth.uid() = created_by);

CREATE POLICY "Creators can delete draft tournaments"
  ON tournaments
  FOR DELETE
  TO authenticated
  USING (auth.uid() = created_by AND status = 'draft');

-- ============================
-- TOURNAMENT PARTICIPANTS
-- ============================

DROP POLICY IF EXISTS "Users can read all tournament participants" ON tournament_participants;
DROP POLICY IF EXISTS "Users can read participants in their tournaments" ON tournament_participants;
DROP POLICY IF EXISTS "Users can join tournaments" ON tournament_participants;
DROP POLICY IF EXISTS "Users can join tournaments with valid code and restrictions" ON tournament_participants;
DROP POLICY IF EXISTS "Users can update their own participation" ON tournament_participants;
DROP POLICY IF EXISTS "Users can update their own participation (forfeit)" ON tournament_participants;
DROP POLICY IF EXISTS "Users can leave tournaments" ON tournament_participants;

CREATE POLICY "Users can read participants of accessible tournaments"
  ON tournament_participants
  FOR SELECT
  TO authenticated
  USING (can_access_tournament(tournament_id, auth.uid()));

-- Intentionally omit INSERT policy: joining must go through RPC (join_tournament_by_code / create_tournament_draft).

CREATE POLICY "Users can update their own participation"
  ON tournament_participants
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can leave tournaments"
  ON tournament_participants
  FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);

-- ============================
-- DAILY SUBMISSIONS
-- ============================

DROP POLICY IF EXISTS "Users can read their own submissions" ON daily_submissions;
DROP POLICY IF EXISTS "Users can read submissions from shared tournaments" ON daily_submissions;
DROP POLICY IF EXISTS "Users can read all submissions" ON daily_submissions;

CREATE POLICY "Users can read their own submissions"
  ON daily_submissions
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "Users can read submissions from shared tournaments"
  ON daily_submissions
  FOR SELECT
  TO authenticated
  USING (share_any_tournament(auth.uid(), user_id));

-- Insert policy remains simple (auth.uid() = user_id). If older policies exist, drop/recreate.
DROP POLICY IF EXISTS "Users can insert their own daily submission" ON daily_submissions;
CREATE POLICY "Users can insert their own daily submission"
  ON daily_submissions
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

-- ============================
-- TOURNAMENT SCORES
-- ============================

DROP POLICY IF EXISTS "Users can read all tournament scores" ON tournament_scores;
DROP POLICY IF EXISTS "Creators can read scores for their tournaments" ON tournament_scores;
DROP POLICY IF EXISTS "Participants can read scores for joined tournaments" ON tournament_scores;
DROP POLICY IF EXISTS "Users can read tournament scores for their tournaments" ON tournament_scores;

CREATE POLICY "Users can read scores for accessible tournaments"
  ON tournament_scores
  FOR SELECT
  TO authenticated
  USING (can_access_tournament(tournament_id, auth.uid()));

-- Remove permissive write policies (writes are handled by SECURITY DEFINER functions / triggers).
DROP POLICY IF EXISTS "Users can insert tournament scores" ON tournament_scores;
DROP POLICY IF EXISTS "Users can update tournament scores" ON tournament_scores;
DROP POLICY IF EXISTS "System can insert tournament scores" ON tournament_scores;
DROP POLICY IF EXISTS "System can update tournament scores" ON tournament_scores;

