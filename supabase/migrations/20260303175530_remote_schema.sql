drop trigger if exists "on_submission_check_leaderboard" on "public"."daily_submissions";

drop trigger if exists "on_submission_update_scores" on "public"."daily_submissions";

drop policy "Users can insert their own daily submission" on "public"."daily_submissions";

drop policy "Users can read submissions from shared tournaments" on "public"."daily_submissions";

drop policy "Users can read their own submissions" on "public"."daily_submissions";

drop policy "Users can read all tournament participants" on "public"."tournament_participants";

drop policy "Users can insert tournament scores" on "public"."tournament_scores";

drop policy "Users can update tournament scores" on "public"."tournament_scores";

drop policy "Users can insert their own profile" on "public"."users";

drop policy "Users can read all user profiles" on "public"."users";

drop policy "Users can update their own profile" on "public"."users";

drop policy "Users can join tournaments" on "public"."tournament_participants";

drop policy "Users can leave tournaments" on "public"."tournament_participants";

drop policy "Users can update their own participation" on "public"."tournament_participants";

alter table "public"."tournaments" drop constraint "valid_date_range";

alter table "public"."users" drop constraint "users_id_fkey";

alter table "public"."tournaments" drop constraint "tournaments_status_check";

drop function if exists "public"."check_all_submissions_complete"(p_tournament_id uuid, p_submission_date date);

drop function if exists "public"."generate_join_code"();

drop function if exists "public"."join_tournament_by_code"(p_join_code text);

drop function if exists "public"."parse_wordle_score"(submission_text text);

drop function if exists "public"."recalculate_tournament_scores"(p_tournament_id uuid, p_submission_date date);

drop function if exists "public"."trigger_leaderboard_update"();

drop function if exists "public"."update_tournament_scores_on_submission"();

drop index if exists "public"."idx_daily_submissions_date";

drop index if exists "public"."idx_daily_submissions_user_id";

drop index if exists "public"."idx_tournament_participants_tournament_id";

drop index if exists "public"."idx_tournament_scores_tournament_id";

drop index if exists "public"."idx_tournaments_join_code";

drop index if exists "public"."idx_tournaments_status";

alter table "public"."daily_submissions" drop column "submission_text";

alter table "public"."daily_submissions" drop column "submitted_at";

alter table "public"."daily_submissions" add column "created_at" timestamp with time zone default now();

alter table "public"."daily_submissions" add column "submission_str" text not null;

alter table "public"."daily_submissions" alter column "id" set default gen_random_uuid();

alter table "public"."tournament_participants" alter column "forfeited" set not null;

alter table "public"."tournament_participants" alter column "id" set default gen_random_uuid();

alter table "public"."tournament_scores" drop column "last_updated";

alter table "public"."tournament_scores" add column "updated_at" timestamp with time zone default now();

alter table "public"."tournament_scores" alter column "id" set default gen_random_uuid();

alter table "public"."tournament_scores" alter column "total_score" set not null;

alter table "public"."tournaments" add column "duration_days" integer;

alter table "public"."tournaments" add column "started_at" timestamp with time zone;

alter table "public"."tournaments" alter column "end_date" drop not null;

alter table "public"."tournaments" alter column "id" set default gen_random_uuid();

alter table "public"."tournaments" alter column "join_code" drop default;

alter table "public"."tournaments" alter column "start_date" drop not null;

alter table "public"."users" add column "auth_user_id" uuid;

alter table "public"."users" add column "recovery_code" text not null;

alter table "public"."users" alter column "id" set default gen_random_uuid();

CREATE INDEX idx_users_auth_user_id ON public.users USING btree (auth_user_id);

CREATE INDEX idx_users_recovery_code ON public.users USING btree (recovery_code);

CREATE UNIQUE INDEX users_recovery_code_key ON public.users USING btree (recovery_code);

alter table "public"."tournaments" add constraint "tournaments_active_has_started_at" CHECK (((status <> 'active'::text) OR (started_at IS NOT NULL))) not valid;

alter table "public"."tournaments" validate constraint "tournaments_active_has_started_at";

alter table "public"."tournaments" add constraint "tournaments_draft_has_duration" CHECK (((status <> 'draft'::text) OR (duration_days IS NOT NULL))) not valid;

alter table "public"."tournaments" validate constraint "tournaments_draft_has_duration";

alter table "public"."tournaments" add constraint "tournaments_duration_days_check" CHECK ((duration_days = ANY (ARRAY[3, 7, 14, 28]))) not valid;

alter table "public"."tournaments" validate constraint "tournaments_duration_days_check";

alter table "public"."users" add constraint "users_auth_user_id_fkey" FOREIGN KEY (auth_user_id) REFERENCES auth.users(id) not valid;

alter table "public"."users" validate constraint "users_auth_user_id_fkey";

alter table "public"."users" add constraint "users_recovery_code_key" UNIQUE using index "users_recovery_code_key";

alter table "public"."tournaments" add constraint "tournaments_status_check" CHECK ((status = ANY (ARRAY['draft'::text, 'active'::text, 'closed'::text]))) not valid;

alter table "public"."tournaments" validate constraint "tournaments_status_check";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.add_daily_penalties()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
INSERT INTO daily_submissions (user_id, submission_date, wordle_score, submitted)
SELECT 
tp.user_id,
CURRENT_DATE,
-10,
false
FROM tournament_participants tp
WHERE tp.tournament_id IN (
SELECT id FROM tournaments 
WHERE status = 'active' 
AND CURRENT_DATE BETWEEN start_date AND end_date
)
AND tp.forfeited = false
AND NOT EXISTS (
SELECT 1 FROM daily_submissions ds 
WHERE ds.user_id = tp.user_id 
AND ds.submission_date = CURRENT_DATE
);
END;
$function$
;

CREATE OR REPLACE FUNCTION public.update_tournament_scores()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
INSERT INTO tournament_scores (tournament_id, user_id, total_score)
SELECT 
tp.tournament_id,
tp.user_id,
COALESCE(SUM(ds.wordle_score), 0) as total_score
FROM tournament_participants tp
LEFT JOIN daily_submissions ds ON ds.user_id = tp.user_id 
AND ds.submission_date >= (SELECT start_date FROM tournaments WHERE id = tp.tournament_id)
AND ds.submission_date <= (SELECT end_date FROM tournaments WHERE id = tp.tournament_id)
WHERE tp.forfeited = false
GROUP BY tp.tournament_id, tp.user_id
ON CONFLICT (tournament_id, user_id) 
DO UPDATE SET 
total_score = EXCLUDED.total_score,
updated_at = NOW();
END;
$function$
;

create policy "Anyone can read daily submissions"
on "public"."daily_submissions"
as permissive
for select
to anon, authenticated
using (true);


create policy "Users can create their submissions"
on "public"."daily_submissions"
as permissive
for insert
to authenticated
with check (((EXISTS ( SELECT 1
   FROM users
  WHERE ((users.auth_user_id = auth.uid()) AND (users.id = daily_submissions.user_id)))) AND (EXISTS ( SELECT 1
   FROM ((tournament_participants tp
     JOIN tournaments t ON ((t.id = tp.tournament_id)))
     JOIN users u ON ((u.id = tp.user_id)))
  WHERE ((u.auth_user_id = auth.uid()) AND (tp.forfeited = false) AND (t.status = 'active'::text) AND (daily_submissions.submission_date >= t.start_date) AND (daily_submissions.submission_date <= t.end_date))))));


create policy "Users can update their submissions"
on "public"."daily_submissions"
as permissive
for update
to authenticated
using ((EXISTS ( SELECT 1
   FROM users
  WHERE ((users.auth_user_id = auth.uid()) AND (users.id = daily_submissions.user_id)))))
with check (((EXISTS ( SELECT 1
   FROM users
  WHERE ((users.auth_user_id = auth.uid()) AND (users.id = daily_submissions.user_id)))) AND (EXISTS ( SELECT 1
   FROM ((tournament_participants tp
     JOIN tournaments t ON ((t.id = tp.tournament_id)))
     JOIN users u ON ((u.id = tp.user_id)))
  WHERE ((u.auth_user_id = auth.uid()) AND (tp.forfeited = false) AND (t.status = 'active'::text) AND (daily_submissions.submission_date >= t.start_date) AND (daily_submissions.submission_date <= t.end_date))))));


create policy "Anyone can read tournament participants"
on "public"."tournament_participants"
as permissive
for select
to anon, authenticated
using (true);


create policy "Anyone can read tournament scores"
on "public"."tournament_scores"
as permissive
for select
to anon, authenticated
using (true);


create policy "Users can create their own scores"
on "public"."tournament_scores"
as permissive
for insert
to authenticated
with check (((EXISTS ( SELECT 1
   FROM users
  WHERE ((users.auth_user_id = auth.uid()) AND (users.id = tournament_scores.user_id)))) AND (EXISTS ( SELECT 1
   FROM tournament_participants tp
  WHERE ((tp.tournament_id = tournament_scores.tournament_id) AND (tp.user_id = tp.user_id) AND (tp.forfeited = false))))));


create policy "Users can update their own scores"
on "public"."tournament_scores"
as permissive
for update
to authenticated
using ((EXISTS ( SELECT 1
   FROM users
  WHERE ((users.auth_user_id = auth.uid()) AND (users.id = tournament_scores.user_id)))))
with check (((EXISTS ( SELECT 1
   FROM users
  WHERE ((users.auth_user_id = auth.uid()) AND (users.id = tournament_scores.user_id)))) AND (EXISTS ( SELECT 1
   FROM tournament_participants tp
  WHERE ((tp.tournament_id = tournament_scores.tournament_id) AND (tp.user_id = tp.user_id) AND (tp.forfeited = false))))));


create policy "Anyone can read tournaments"
on "public"."tournaments"
as permissive
for select
to anon, authenticated
using (true);


create policy "Authenticated users can create tournaments"
on "public"."tournaments"
as permissive
for insert
to authenticated
with check ((created_by IN ( SELECT users.id
   FROM users
  WHERE (users.auth_user_id = auth.uid()))));


create policy "Creator can delete their draft tournaments"
on "public"."tournaments"
as permissive
for delete
to authenticated
using (((status = 'draft'::text) AND (EXISTS ( SELECT 1
   FROM users
  WHERE ((users.auth_user_id = auth.uid()) AND (users.id = tournaments.created_by))))));


create policy "Creator can update their tournaments"
on "public"."tournaments"
as permissive
for update
to authenticated
using ((EXISTS ( SELECT 1
   FROM users
  WHERE ((users.auth_user_id = auth.uid()) AND (users.id = tournaments.created_by)))))
with check ((EXISTS ( SELECT 1
   FROM users
  WHERE ((users.auth_user_id = auth.uid()) AND (users.id = tournaments.created_by)))));


create policy "Anyone can read users for recovery code lookup"
on "public"."users"
as permissive
for select
to anon, authenticated
using (true);


create policy "Users can create their own profile"
on "public"."users"
as permissive
for insert
to authenticated
with check (((id = auth.uid()) AND (auth_user_id = auth.uid())));


create policy "Users can join tournaments"
on "public"."tournament_participants"
as permissive
for insert
to authenticated
with check ((EXISTS ( SELECT 1
   FROM users
  WHERE ((users.auth_user_id = auth.uid()) AND (users.id = tournament_participants.user_id)))));


create policy "Users can leave tournaments"
on "public"."tournament_participants"
as permissive
for delete
to authenticated
using ((EXISTS ( SELECT 1
   FROM users
  WHERE ((users.auth_user_id = auth.uid()) AND (users.id = tournament_participants.user_id)))));


create policy "Users can update their own participation"
on "public"."tournament_participants"
as permissive
for update
to authenticated
using ((EXISTS ( SELECT 1
   FROM users
  WHERE ((users.auth_user_id = auth.uid()) AND (users.id = tournament_participants.user_id)))))
with check ((EXISTS ( SELECT 1
   FROM users
  WHERE ((users.auth_user_id = auth.uid()) AND (users.id = tournament_participants.user_id)))));



