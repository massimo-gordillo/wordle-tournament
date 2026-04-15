-- Create public.users profile only when an auth user is confirmed.
-- This keeps local environments safe by skipping trigger creation if auth.users is unavailable.

CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_display_name text;
  v_is_confirmed boolean;
BEGIN
  v_is_confirmed :=
    NULLIF(to_jsonb(NEW) ->> 'confirmed_at', '') IS NOT NULL
    OR NULLIF(to_jsonb(NEW) ->> 'email_confirmed_at', '') IS NOT NULL
    OR NULLIF(to_jsonb(NEW) ->> 'phone_confirmed_at', '') IS NOT NULL;

  IF NOT v_is_confirmed THEN
    RETURN NEW;
  END IF;

  v_display_name := COALESCE(
    NULLIF(trim(NEW.raw_user_meta_data ->> 'display_name'), ''),
    NULLIF(trim(split_part(NEW.email, '@', 1)), ''),
    'Player'
  );

  INSERT INTO public.users (id, display_name)
  VALUES (NEW.id, v_display_name)
  ON CONFLICT (id) DO NOTHING;

  RETURN NEW;
END;
$$;

DO $$
BEGIN
  IF to_regclass('auth.users') IS NULL THEN
    RAISE NOTICE 'Skipping auth.users trigger setup because auth.users does not exist in this environment.';
    RETURN;
  END IF;

  EXECUTE 'DROP TRIGGER IF EXISTS on_auth_user_created_public_profile ON auth.users';
  EXECUTE 'DROP TRIGGER IF EXISTS on_auth_user_confirmed_public_profile ON auth.users';

  EXECUTE '
    CREATE TRIGGER on_auth_user_confirmed_public_profile
      AFTER INSERT OR UPDATE ON auth.users
      FOR EACH ROW
      EXECUTE FUNCTION public.handle_new_auth_user()
  ';
END;
$$;
