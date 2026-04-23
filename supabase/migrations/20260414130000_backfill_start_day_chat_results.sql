CREATE OR REPLACE FUNCTION "public"."start_draft_tournament"("p_tournament_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_created_by uuid;
  v_status text;
  v_start_date date;
  v_end_date date;
  v_duration_days integer;
  v_today date;
  v_new_end_date date;
  v_participant_count integer;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = 'P0001';
  END IF;

  SELECT created_by, status, start_date, end_date
  INTO v_created_by, v_status, v_start_date, v_end_date
  FROM tournaments
  WHERE id = p_tournament_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'TOURNAMENT_NOT_FOUND' USING ERRCODE = 'P0001';
  END IF;

  IF v_created_by <> v_uid THEN
    RAISE EXCEPTION 'ONLY_CREATOR_CAN_START' USING ERRCODE = 'P0001';
  END IF;

  IF v_status <> 'draft' THEN
    RAISE EXCEPTION 'TOURNAMENT_NOT_DRAFT' USING ERRCODE = 'P0001';
  END IF;

  SELECT COUNT(*)
  INTO v_participant_count
  FROM tournament_participants
  WHERE tournament_id = p_tournament_id;

  IF v_participant_count < 2 THEN
    RAISE EXCEPTION 'NOT_ENOUGH_PLAYERS' USING ERRCODE = 'P0001';
  END IF;

  v_duration_days := (v_end_date - v_start_date) + 1;
  IF v_duration_days < 1 THEN
    RAISE EXCEPTION 'INVALID_TOURNAMENT_DURATION' USING ERRCODE = 'P0001';
  END IF;

  v_today := (now() AT TIME ZONE 'America/New_York')::date;
  v_new_end_date := v_today + (v_duration_days - 1);

  UPDATE tournaments
  SET
    status = 'active',
    start_date = v_today,
    end_date = v_new_end_date
  WHERE id = p_tournament_id
    AND status = 'draft';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'TOURNAMENT_NOT_DRAFT' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO tournament_chat (
    tournament_id,
    user_id,
    message,
    message_type,
    submission_date,
    daily_submission_id
  )
  SELECT
    p_tournament_id,
    ds.user_id,
    'result',
    'result',
    ds.submission_date,
    ds.id
  FROM tournament_participants tp
  JOIN daily_submissions ds
    ON ds.user_id = tp.user_id
  WHERE tp.tournament_id = p_tournament_id
    AND ds.submission_date = v_today
    AND NOT EXISTS (
      SELECT 1
      FROM tournament_chat tc
      WHERE tc.tournament_id = p_tournament_id
        AND tc.daily_submission_id = ds.id
    );
END;
$$;
