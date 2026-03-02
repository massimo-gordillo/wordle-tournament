/*
  # Fix Tournament SELECT Policy to Prevent Recursion

  ## Problem
  The SELECT policy for tournaments causes infinite recursion when combined with INSERT:
  - SELECT policy has an EXISTS subquery checking tournament_participants
  - tournament_participants references tournaments.id
  - When INSERT happens, it triggers SELECT which triggers the EXISTS check
  - This creates a circular dependency

  ## Solution
  Split the SELECT policy into two separate policies:
  1. Simple policy for creators (no subquery)
  2. Policy for participants (with subquery)
  
  PostgreSQL will evaluate these independently and the creator check will succeed
  immediately for new tournaments without triggering the participant check.

  ## Changes
  - Drop the combined SELECT policy
  - Create two separate SELECT policies
*/

-- Drop the problematic combined policy
DROP POLICY IF EXISTS "Users can read tournaments they participate in" ON tournaments;

-- Create separate policies for creators and participants
CREATE POLICY "Tournament creators can read their tournaments"
  ON tournaments FOR SELECT
  TO authenticated
  USING (created_by = auth.uid());

CREATE POLICY "Tournament participants can read tournaments they joined"
  ON tournaments FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM tournament_participants
      WHERE tournament_participants.tournament_id = tournaments.id
      AND tournament_participants.user_id = auth.uid()
    )
  );
