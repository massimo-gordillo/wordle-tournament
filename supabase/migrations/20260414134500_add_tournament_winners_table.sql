CREATE TABLE IF NOT EXISTS public.tournament_winners (
  tournament_id uuid NOT NULL,
  user_id uuid NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT tournament_winners_pkey PRIMARY KEY (tournament_id, user_id),
  CONSTRAINT tournament_winners_tournament_id_fkey
    FOREIGN KEY (tournament_id) REFERENCES public.tournaments(id) ON DELETE CASCADE,
  CONSTRAINT tournament_winners_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_tournament_winners_user_id
ON public.tournament_winners (user_id);

CREATE OR REPLACE FUNCTION public.refresh_tournament_winners(p_tournament_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_top_score integer;
BEGIN
  DELETE FROM public.tournament_winners
  WHERE tournament_id = p_tournament_id;

  SELECT MAX(ts.total_score)
  INTO v_top_score
  FROM public.tournament_scores ts
  JOIN public.tournament_participants tp
    ON tp.tournament_id = ts.tournament_id
    AND tp.user_id = ts.user_id
  WHERE ts.tournament_id = p_tournament_id
    AND tp.forfeited = false;

  IF v_top_score IS NULL THEN
    RETURN;
  END IF;

  INSERT INTO public.tournament_winners (tournament_id, user_id)
  SELECT
    ts.tournament_id,
    ts.user_id
  FROM public.tournament_scores ts
  JOIN public.tournament_participants tp
    ON tp.tournament_id = ts.tournament_id
    AND tp.user_id = ts.user_id
  WHERE ts.tournament_id = p_tournament_id
    AND tp.forfeited = false
    AND ts.total_score = v_top_score;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_tournament_winners_on_close()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.status = 'closed' AND OLD.status IS DISTINCT FROM 'closed' THEN
    PERFORM public.refresh_tournament_winners(NEW.id);
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_tournament_winners_on_close_trigger ON public.tournaments;

CREATE TRIGGER set_tournament_winners_on_close_trigger
BEFORE UPDATE OF status ON public.tournaments
FOR EACH ROW
EXECUTE FUNCTION public.set_tournament_winners_on_close();

DO $$
DECLARE
  v_closed record;
BEGIN
  FOR v_closed IN
    SELECT id
    FROM public.tournaments
    WHERE status = 'closed'
  LOOP
    PERFORM public.refresh_tournament_winners(v_closed.id);
  END LOOP;
END;
$$;

ALTER TABLE public.tournament_winners ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read winners for accessible tournaments" ON public.tournament_winners;

CREATE POLICY "Users can read winners for accessible tournaments"
ON public.tournament_winners
FOR SELECT
TO authenticated
USING (public.can_access_tournament(tournament_id, auth.uid()));

GRANT SELECT ON TABLE public.tournament_winners TO authenticated;
GRANT SELECT ON TABLE public.tournament_winners TO service_role;
