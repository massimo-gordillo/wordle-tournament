-- Fix security posture on fresh environments:
-- both tables exist but were missing explicit RLS enablement.
ALTER TABLE IF EXISTS public.app_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.tournament_bans ENABLE ROW LEVEL SECURITY;
