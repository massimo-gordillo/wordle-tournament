-- Explicit Data API grants for public schema objects (Supabase changelog 45329).
-- New projects (from 2026-05-30) and existing projects (from 2026-10-30) no longer
-- auto-expose new public tables/functions; grants must be declared in migrations.
-- https://supabase.com/changelog/45329-breaking-change-tables-not-exposed-to-data-and-graphql-api-automatically

-- Tables (RLS still enforces row access; grants allow PostgREST to see the relation)
GRANT ALL ON TABLE public.app_config TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.daily_submissions TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.tournament_bans TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.tournament_chat TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.tournament_participants TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.tournament_scores TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.tournaments TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.users TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.tournament_winners TO anon, authenticated, service_role;

-- RPC and SECURITY DEFINER functions exposed via PostgREST
GRANT ALL ON FUNCTION public.can_access_tournament(uuid, uuid) TO anon, authenticated, service_role;
GRANT ALL ON FUNCTION public.cancel_tournament_draft(uuid) TO anon, authenticated, service_role;
GRANT ALL ON FUNCTION public.check_all_submissions_complete(uuid, date) TO anon, authenticated, service_role;
GRANT ALL ON FUNCTION public.create_tournament_draft(text, date, date) TO anon, authenticated, service_role;
GRANT ALL ON FUNCTION public.enforce_daily_submission_cutoff() TO anon, authenticated, service_role;
GRANT ALL ON FUNCTION public.forfeit_tournament(uuid) TO anon, authenticated, service_role;
GRANT ALL ON FUNCTION public.forfeit_tournament_internal(uuid, uuid) TO anon, authenticated, service_role;
GRANT ALL ON FUNCTION public.generate_join_code() TO anon, authenticated, service_role;
GRANT ALL ON FUNCTION public.get_app_config() TO anon, authenticated, service_role;
GRANT ALL ON FUNCTION public.get_tournament_limit_info() TO anon, authenticated, service_role;
GRANT ALL ON FUNCTION public.join_tournament_by_code(text) TO anon, authenticated, service_role;
GRANT ALL ON FUNCTION public.kick_tournament_participant(uuid, uuid) TO anon, authenticated, service_role;
GRANT ALL ON FUNCTION public.leave_draft_tournament(uuid) TO anon, authenticated, service_role;
GRANT ALL ON FUNCTION public.parse_wordle_score(text) TO anon, authenticated, service_role;
GRANT ALL ON FUNCTION public.recalculate_tournament_scores(uuid, date) TO anon, authenticated, service_role;
GRANT ALL ON FUNCTION public.run_daily_cron() TO anon, authenticated, service_role;
GRANT ALL ON FUNCTION public.run_daily_cron_for_active_tournaments_range(date) TO anon, authenticated, service_role;
GRANT ALL ON FUNCTION public.run_daily_cron_for_date(date) TO anon, authenticated, service_role;
GRANT ALL ON FUNCTION public.run_daily_cron_if_eastern_cutoff() TO anon, authenticated, service_role;
GRANT ALL ON FUNCTION public.share_any_tournament(uuid, uuid) TO anon, authenticated, service_role;
GRANT ALL ON FUNCTION public.start_draft_tournament(uuid) TO anon, authenticated, service_role;
GRANT ALL ON FUNCTION public.trigger_leaderboard_update() TO anon, authenticated, service_role;
GRANT ALL ON FUNCTION public.update_tournament_scores_on_submission() TO anon, authenticated, service_role;

-- Account deletion RPC: authenticated users and service role only (edge function uses service_role)
REVOKE ALL ON FUNCTION public.anonymize_my_account() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.anonymize_my_account() TO authenticated, service_role;
