-- Re-schedule edge-run-daily-cron using app.settings.* (if available) or Vault secrets.
-- Keep running both 03:00 and 04:00 UTC; edge handler enforces 11 PM ET.

CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

DO $$
DECLARE
  v_project_url text := NULLIF(current_setting('app.settings.supabase_url', true), '');
  v_service_role_key text := NULLIF(current_setting('app.settings.service_role_key', true), '');
  v_headers jsonb;
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

  IF v_project_url IS NULL OR v_service_role_key IS NULL THEN
    RAISE NOTICE
      'Skipping edge-run-daily-cron HTTP schedule in this migration: missing app.settings.supabase_url / app.settings.service_role_key (and Vault fallbacks if applicable). A later migration may install a local SQL fallback or reschedule once credentials exist.';
    RETURN;
  END IF;

  v_headers := jsonb_build_object(
    'Content-Type', 'application/json',
    'Authorization', 'Bearer ' || v_service_role_key,
    'apikey', v_service_role_key
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
