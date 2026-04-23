-- Re-schedule daily cron with environment-aware behavior:
-- - Preferred: invoke edge-run-daily-cron over HTTP with service-role JWT
-- - Fallback (local dev): call run_daily_cron_for_date directly in SQL when
--   app.settings/vault credentials are unavailable.
--
-- This keeps remote behavior secure while allowing local migration pushes
-- without privileged ALTER DATABASE config changes.

CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

DO $$
DECLARE
  v_project_url text := NULLIF(current_setting('app.settings.supabase_url', true), '');
  v_service_role_key text := NULLIF(current_setting('app.settings.service_role_key', true), '');
  v_headers jsonb;
  v_can_call_edge boolean := false;
BEGIN
  -- Optional hosted Supabase path: resolve values from Vault if available.
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

    RAISE NOTICE 'Scheduled edge-run-daily-cron via HTTP (secure path).';
  ELSE
    PERFORM cron.schedule(
      'edge-run-daily-cron-03utc',
      '0 3 * * *',
      $sql$
      SELECT public.run_daily_cron_for_date((now() AT TIME ZONE 'America/New_York')::date);
      $sql$
    );

    PERFORM cron.schedule(
      'edge-run-daily-cron-04utc',
      '0 4 * * *',
      $sql$
      SELECT public.run_daily_cron_for_date((now() AT TIME ZONE 'America/New_York')::date);
      $sql$
    );

    RAISE NOTICE 'Scheduled local fallback (direct SQL) because edge HTTP credentials were unavailable.';
  END IF;
END
$$;
