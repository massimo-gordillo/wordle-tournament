-- Ensure a single default app_config row exists (column defaults supply limits/points).
INSERT INTO public.app_config (key)
VALUES ('default')
ON CONFLICT (key) DO NOTHING;
