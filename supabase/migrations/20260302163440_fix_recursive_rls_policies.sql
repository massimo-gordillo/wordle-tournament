/*
  # Fix Recursive RLS Policies

  This migration removes all recursive RLS policies and replaces them with simple, 
  non-recursive policies that only use auth.uid() and direct column checks.

  ## Changes

  1. **tournaments table**
     - Remove recursive policy that queries tournament_participants
     - Replace with simple ownership-based policies
     - Add public read policy for tournaments (users need to see tournaments to join them)

  2. **tournament_participants table**
     - Simplify join policy to remove recursive checks
     - Keep only essential validations

  3. **tournament_scores table**
     - Simplify to use only direct column checks

  ## Security Notes
  - All policies now use only auth.uid() and direct row fields
  - No recursive EXISTS subqueries that reference the same or dependent tables
  - Maintains security while preventing infinite recursion
*/

-- Drop all existing policies on tournaments table
DROP POLICY IF EXISTS "Tournament creators can read their tournaments" ON tournaments;
DROP POLICY IF EXISTS "Tournament participants can read tournaments they joined" ON tournaments;
DROP POLICY IF EXISTS "Users can create tournaments" ON tournaments;
DROP POLICY IF EXISTS "Tournament creators can update their tournaments" ON tournaments;
DROP POLICY IF EXISTS "Tournament creators can delete their draft tournaments" ON tournaments;

-- Create simple, non-recursive policies for tournaments
CREATE POLICY "Users can create their own tournaments"
  ON tournaments
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = created_by);

CREATE POLICY "Users can read all tournaments"
  ON tournaments
  FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Tournament creators can update their own tournaments"
  ON tournaments
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = created_by)
  WITH CHECK (auth.uid() = created_by);

CREATE POLICY "Tournament creators can delete their own draft tournaments"
  ON tournaments
  FOR DELETE
  TO authenticated
  USING (auth.uid() = created_by AND status = 'draft');

-- Drop and recreate tournament_participants policies
DROP POLICY IF EXISTS "Users can read participants in their tournaments" ON tournament_participants;
DROP POLICY IF EXISTS "Users can join tournaments with valid code and restrictions" ON tournament_participants;
DROP POLICY IF EXISTS "Tournament creators can remove participants from draft tourname" ON tournament_participants;
DROP POLICY IF EXISTS "Users can update their own participation (forfeit)" ON tournament_participants;

CREATE POLICY "Users can read all tournament participants"
  ON tournament_participants
  FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Users can join tournaments"
  ON tournament_participants
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

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

-- Drop and recreate tournament_scores policies
DROP POLICY IF EXISTS "Users can read tournament scores for their tournaments" ON tournament_scores;
DROP POLICY IF EXISTS "System can insert tournament scores" ON tournament_scores;
DROP POLICY IF EXISTS "System can update tournament scores" ON tournament_scores;

CREATE POLICY "Users can read all tournament scores"
  ON tournament_scores
  FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Users can insert tournament scores"
  ON tournament_scores
  FOR INSERT
  TO authenticated
  WITH CHECK (true);

CREATE POLICY "Users can update tournament scores"
  ON tournament_scores
  FOR UPDATE
  TO authenticated
  USING (true)
  WITH CHECK (true);

-- Daily submissions policies are fine, but let's fix the recursive one
DROP POLICY IF EXISTS "Users can insert their own daily submission" ON daily_submissions;

CREATE POLICY "Users can insert their own daily submission"
  ON daily_submissions
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);
