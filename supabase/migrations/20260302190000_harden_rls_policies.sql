/*
  # Harden RLS Policies (Non‑recursive)

  Restores tighter access control without recursive RLS:

  - Tournaments:
    - Authenticated users can create tournaments they own
    - Only creators and participants can read tournaments
    - Only creators can update/delete their tournaments (delete only while draft)

  - Tournament participants:
    - Keep simple, non‑recursive rules (no self‑referential COUNT(*) queries)

  - Tournament scores:
    - Scores are readable only for creators/participants
    - Writes remain handled by database triggers / privileged functions
*/

-- ============================
-- TOURNAMENTS
-- ============================

-- Drop overly-permissive policies if they exist
DROP POLICY IF EXISTS "Users can read all tournaments" ON tournaments;
DROP POLICY IF EXISTS "Users can create their own tournaments" ON tournaments;
DROP POLICY IF EXISTS "Tournament creators can update their own tournaments" ON tournaments;
DROP POLICY IF EXISTS "Tournament creators can delete their own draft tournaments" ON tournaments;

-- Create scoped, non-recursive policies
CREATE POLICY "Users can create tournaments they own"
  ON tournaments
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = created_by);

CREATE POLICY "Creators can read their tournaments"
  ON tournaments
  FOR SELECT
  TO authenticated
  USING (auth.uid() = created_by);

CREATE POLICY "Participants can read joined tournaments"
  ON tournaments
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM tournament_participants tp
      WHERE tp.tournament_id = tournaments.id
        AND tp.user_id = auth.uid()
    )
  );

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
-- TOURNAMENT SCORES
-- ============================

-- Replace open policies with scoped read access
DROP POLICY IF EXISTS "Users can read all tournament scores" ON tournament_scores;

CREATE POLICY "Creators can read scores for their tournaments"
  ON tournament_scores
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM tournaments t
      WHERE t.id = tournament_scores.tournament_id
        AND t.created_by = auth.uid()
    )
  );

CREATE POLICY "Participants can read scores for joined tournaments"
  ON tournament_scores
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM tournament_participants tp
      WHERE tp.tournament_id = tournament_scores.tournament_id
        AND tp.user_id = auth.uid()
    )
  );

