/*
  # Fix overly-permissive users UPDATE policy

  Supabase dashboard warning:
  - Table: public.users
  - Policy: "Users can update their auth session"
  - Issue: USING (true) / WITH CHECK (true) on UPDATE effectively disables RLS.

  This migration removes that broad policy so that only the stricter
  "Users can update their own profile" policy remains in effect.
*/

DROP POLICY IF EXISTS "Users can update their auth session" ON users;

