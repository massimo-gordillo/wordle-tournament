/*
  # Access helper functions for non-recursive RLS

  These SECURITY DEFINER helpers let us write RLS policies without
  self-referencing queries that can recurse under RLS.
*/

CREATE OR REPLACE FUNCTION can_access_tournament(p_tournament_id uuid, p_user_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    EXISTS (
      SELECT 1
      FROM tournaments t
      WHERE t.id = p_tournament_id
        AND t.created_by = p_user_id
    )
    OR EXISTS (
      SELECT 1
      FROM tournament_participants tp
      WHERE tp.tournament_id = p_tournament_id
        AND tp.user_id = p_user_id
    );
$$;

CREATE OR REPLACE FUNCTION share_any_tournament(p_user_a uuid, p_user_b uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM tournament_participants a
    JOIN tournament_participants b
      ON a.tournament_id = b.tournament_id
    WHERE a.user_id = p_user_a
      AND b.user_id = p_user_b
  );
$$;

REVOKE ALL ON FUNCTION can_access_tournament(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION can_access_tournament(uuid, uuid) TO authenticated;

REVOKE ALL ON FUNCTION share_any_tournament(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION share_any_tournament(uuid, uuid) TO authenticated;

