/*
  # Add cancelled status to tournaments

  1. Changes
    - Update the status CHECK constraint to include 'cancelled' as a valid status
    - Allows tournament creators to cancel tournaments
  
  2. Security
    - No changes to RLS policies
*/

-- Drop the old constraint
ALTER TABLE tournaments DROP CONSTRAINT IF EXISTS tournaments_status_check;

-- Add the new constraint with 'cancelled' status
ALTER TABLE tournaments ADD CONSTRAINT tournaments_status_check 
  CHECK (status IN ('draft', 'active', 'closed', 'cancelled'));
