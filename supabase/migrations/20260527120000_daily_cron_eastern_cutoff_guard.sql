-- Daily cron: derive run date and cutoff hour in America/New_York (never session UTC).
-- Edge function and pg_cron both call run_daily_cron_if_eastern_cutoff() so 11 PM ET
-- penalties attach to the correct calendar day (e.g. 04:00 UTC still = prior ET date).

CREATE OR REPLACE FUNCTION public.run_daily_cron_if_eastern_cutoff()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_est_now timestamp;
  v_today date;
  v_hour integer;
  v_cutoff_hour integer;
BEGIN
  v_est_now := (now() AT TIME ZONE 'America/New_York');
  v_today := v_est_now::date;
  v_hour := EXTRACT(HOUR FROM v_est_now)::integer;

  SELECT cutoff_hour_est
  INTO v_cutoff_hour
  FROM app_config
  ORDER BY updated_at DESC
  LIMIT 1;

  IF v_cutoff_hour IS NULL THEN
    v_cutoff_hour := 23;
  END IF;

  IF v_hour <> v_cutoff_hour THEN
    RETURN jsonb_build_object(
      'success', true,
      'skipped', true,
      'message', 'Skipped: not cutoff hour in America/New_York.',
      'hour_et', v_hour,
      'cutoff_hour_et', v_cutoff_hour,
      'run_date_et', v_today
    );
  END IF;

  PERFORM run_daily_cron_for_date(v_today);

  RETURN jsonb_build_object(
    'success', true,
    'skipped', false,
    'run_date_et', v_today,
    'hour_et', v_hour,
    'cutoff_hour_et', v_cutoff_hour
  );
END;
$$;

ALTER FUNCTION public.run_daily_cron_if_eastern_cutoff() OWNER TO postgres;

GRANT ALL ON FUNCTION public.run_daily_cron_if_eastern_cutoff() TO anon;
GRANT ALL ON FUNCTION public.run_daily_cron_if_eastern_cutoff() TO authenticated;
GRANT ALL ON FUNCTION public.run_daily_cron_if_eastern_cutoff() TO service_role;

-- Re-schedule pg_cron: HTTP to edge (edge calls RPC) or SQL fallback with eastern guard.
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

DO $$
DECLARE
  v_project_url text := NULLIF(current_setting('app.settings.supabase_url', true), '');
  v_service_role_key text := NULLIF(current_setting('app.settings.service_role_key', true), '');
  v_headers jsonb;
  v_can_call_edge boolean := false;
BEGIN
  IF (v_project_url IS NULL OR v_service_role_key IS NULL)
    AND to_regclass('vault.decrypted_secrets') IS NOT NULL THEN
    IF v_project_url IS NULL THEN
      EXECUTE $q$
        SELECT decrypted_secret
        FROM vault.decrypted_secrets
        WHERE name = 'app.settings.supabase_url'
        ORDER BY created_at DESC
        LIMIT 1
      $q$
      INTO v_project_url;
    END IF;

    IF v_service_role_key IS NULL THEN
      EXECUTE $q$
        SELECT decrypted_secret
        FROM vault.decrypted_secrets
        WHERE name = 'app.settings.service_role_key'
        ORDER BY created_at DESC
        LIMIT 1
      $q$
      INTO v_service_role_key;
    END IF;
  END IF;

  v_can_call_edge := v_project_url IS NOT NULL AND v_service_role_key IS NOT NULL;

  PERFORM cron.unschedule(jobid)
  FROM cron.job
  WHERE jobname IN ('edge-run-daily-cron-03utc', 'edge-run-daily-cron-04utc');

  IF v_can_call_edge THEN
    v_headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_service_role_key,
      'apikey', v_service_role_key
    );

    PERFORM cron.schedule(
      'edge-run-daily-cron-03utc',
      '0 3 * * *',
      format(
        $sql$
        SELECT net.http_post(
          url := %L,
          headers := %L::jsonb,
          body := '{}'::jsonb
        );
        $sql$,
        v_project_url || '/functions/v1/edge-run-daily-cron',
        v_headers::text
      )
    );

    PERFORM cron.schedule(
      'edge-run-daily-cron-04utc',
      '0 4 * * *',
      format(
        $sql$
        SELECT net.http_post(
          url := %L,
          headers := %L::jsonb,
          body := '{}'::jsonb
        );
        $sql$,
        v_project_url || '/functions/v1/edge-run-daily-cron',
        v_headers::text
      )
    );

    RAISE NOTICE 'Scheduled edge-run-daily-cron via HTTP.';
  ELSE
    PERFORM cron.schedule(
      'edge-run-daily-cron-03utc',
      '0 3 * * *',
      $sql$
      SELECT public.run_daily_cron_if_eastern_cutoff();
      $sql$
    );

    PERFORM cron.schedule(
      'edge-run-daily-cron-04utc',
      '0 4 * * *',
      $sql$
      SELECT public.run_daily_cron_if_eastern_cutoff();
      $sql$
    );

    RAISE NOTICE 'Scheduled local SQL fallback with eastern cutoff guard.';
  END IF;
END
$$;
