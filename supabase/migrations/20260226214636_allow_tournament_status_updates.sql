/*
  # Allow tournament creators to update tournament status

  1. Changes
    - Update the tournaments UPDATE policy to allow creators to update status from draft to active or cancelled
    - This enables starting tournaments and cancelling them
  
  2. Security
    - Only tournament creators can update their tournaments
    - No other changes to permissions
*/

-- Drop the old policy
DROP POLICY IF EXISTS "Tournament creators can update their draft tournaments" ON tournaments;

-- Create new policy that allows creators to update their tournaments
CREATE POLICY "Tournament creators can update their tournaments"
  ON tournaments FOR UPDATE
  TO authenticated
  USING (created_by = auth.uid())
  WITH CHECK (created_by = auth.uid());
