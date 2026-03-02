/*
  # Fix Infinite Recursion in Tournament RLS Policies

  ## Problem
  The INSERT policy for tournaments had a subquery that caused infinite recursion:
  - INSERT policy checked COUNT(*) FROM tournaments
  - That SELECT triggered the SELECT policy
  - SELECT policy referenced tournament_participants which references tournaments
  - This created a circular dependency

  ## Solution
  1. Drop and recreate the INSERT policy without the COUNT check
  2. The 4-tournament limit will be enforced at the application level instead
  3. Keep other policies unchanged as they don't cause recursion

  ## Changes
  - Drop problematic INSERT policy
  - Create new simplified INSERT policy
  - All other policies remain the same
*/

-- Drop the problematic policy
DROP POLICY IF EXISTS "Users can create tournaments if they have less than 4" ON tournaments;

-- Create a new simplified INSERT policy without the recursive check
CREATE POLICY "Users can create tournaments"
  ON tournaments FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = created_by);
