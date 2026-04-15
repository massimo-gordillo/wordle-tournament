-- Schedule the edge-run-daily-cron edge function using pg_cron + pg_net.
-- We schedule at both 03:00 and 04:00 UTC and let the edge function
-- itself guard on 11 PM America/New_York so DST is handled correctly.

CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

DO $$
DECLARE
  v_project_url text := current_setting('app.settings.supabase_url', true);
  v_service_role_key text := current_setting('app.settings.service_role_key', true);
  v_headers jsonb;
BEGIN
  IF v_project_url IS NULL OR v_project_url = '' THEN
    RAISE NOTICE 'Skipping cron schedule setup: app.settings.supabase_url is unavailable in this environment.';
    RETURN;
  END IF;

  IF v_service_role_key IS NULL OR v_service_role_key = '' THEN
    RAISE NOTICE 'Skipping cron schedule setup: app.settings.service_role_key is unavailable in this environment.';
    RETURN;
  END IF;

  v_headers := jsonb_build_object(
    'Content-Type', 'application/json',
    'Authorization', 'Bearer ' || v_service_role_key
  );

  PERFORM cron.unschedule(jobid)
  FROM cron.job
  WHERE jobname IN ('edge-run-daily-cron-03utc', 'edge-run-daily-cron-04utc');

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
END
$$;
