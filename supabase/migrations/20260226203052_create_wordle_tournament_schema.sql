/*
  # Wordle Tournament App Database Schema

  ## Overview
  Creates the complete database schema for a Wordle tournament tracking app with daily submissions,
  tournament management, scoring, and user participation tracking.

  ## New Tables

  1. **users**
     - `id` (uuid, primary key) - Links to auth.users
     - `display_name` (text) - User's chosen display name
     - `created_at` (timestamptz) - Account creation timestamp

  2. **tournaments**
     - `id` (uuid, primary key)
     - `name` (text) - Tournament name
     - `join_code` (text, unique) - Shareable code to join tournament
     - `start_date` (date) - Tournament start date
     - `end_date` (date) - Tournament end date
     - `status` (text) - One of: 'draft', 'active', 'closed'
     - `created_by` (uuid) - Foreign key to users
     - `created_at` (timestamptz)

  3. **tournament_participants**
     - `id` (uuid, primary key)
     - `tournament_id` (uuid) - Foreign key to tournaments
     - `user_id` (uuid) - Foreign key to users
     - `forfeited` (boolean) - Whether user has forfeited
     - `joined_at` (timestamptz)
     - UNIQUE constraint on (tournament_id, user_id)

  4. **daily_submissions**
     - `id` (uuid, primary key)
     - `user_id` (uuid) - Foreign key to users
     - `submission_date` (date) - Date of the Wordle game
     - `submission_text` (text) - Full Wordle share output
     - `wordle_score` (integer) - Calculated score (20/8/6/4/2/1/-2)
     - `submitted_at` (timestamptz)
     - UNIQUE constraint on (user_id, submission_date)

  5. **tournament_scores**
     - `id` (uuid, primary key)
     - `tournament_id` (uuid) - Foreign key to tournaments
     - `user_id` (uuid) - Foreign key to users
     - `total_score` (integer) - Sum of all daily scores
     - `last_updated` (timestamptz)
     - UNIQUE constraint on (tournament_id, user_id)

  ## Security
  - Enable RLS on all tables
  - Users can read their own data
  - Users can create/join tournaments with restrictions
  - Tournament creators have special permissions in draft mode
  - Participants can view tournament data
  - One submission per user per day enforced

  ## Functions
  - Function to calculate Wordle score from submission text
  - Function to generate unique join codes
  - Trigger to update tournament scores on new submissions
*/

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Function to generate random join code
CREATE OR REPLACE FUNCTION generate_join_code()
RETURNS text AS $$
DECLARE
  chars text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  result text := '';
  i integer;
BEGIN
  FOR i IN 1..6 LOOP
    result := result || substr(chars, floor(random() * length(chars) + 1)::integer, 1);
  END LOOP;
  RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Function to parse Wordle score from submission text
CREATE OR REPLACE FUNCTION parse_wordle_score(submission_text text)
RETURNS integer AS $$
DECLARE
  guess_count integer;
  first_line text;
BEGIN
  -- Extract first line (e.g., "Wordle 932 3/6")
  first_line := split_part(submission_text, E'\n', 1);
  
  -- Extract the X from "X/6" pattern
  guess_count := (regexp_match(first_line, '(\d+)/\d+'))[1]::integer;
  
  -- If guess_count is null or invalid, try counting emoji rows
  IF guess_count IS NULL OR guess_count < 1 THEN
    -- Count rows with Wordle emojis
    guess_count := (
      SELECT COUNT(*)
      FROM unnest(string_to_array(submission_text, E'\n')) AS line
      WHERE line ~ '[🟩🟨⬜⬛]'
    );
  END IF;
  
  -- Return score based on guess count
  RETURN CASE
    WHEN guess_count = 1 THEN 20
    WHEN guess_count = 2 THEN 8
    WHEN guess_count = 3 THEN 6
    WHEN guess_count = 4 THEN 4
    WHEN guess_count = 5 THEN 2
    WHEN guess_count = 6 THEN 1
    ELSE -2
  END;
EXCEPTION
  WHEN OTHERS THEN
    RETURN -2;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ============================================================================
-- USERS TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS users (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name text NOT NULL,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE users ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read all user profiles"
  ON users FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Users can insert their own profile"
  ON users FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update their own profile"
  ON users FOR UPDATE
  TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- ============================================================================
-- TOURNAMENTS TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS tournaments (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  name text NOT NULL,
  join_code text UNIQUE NOT NULL DEFAULT generate_join_code(),
  start_date date NOT NULL,
  end_date date NOT NULL,
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'active', 'closed')),
  created_by uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now(),
  CONSTRAINT valid_date_range CHECK (end_date >= start_date)
);

CREATE INDEX IF NOT EXISTS idx_tournaments_created_by ON tournaments(created_by);
CREATE INDEX IF NOT EXISTS idx_tournaments_status ON tournaments(status);
CREATE INDEX IF NOT EXISTS idx_tournaments_join_code ON tournaments(join_code);

ALTER TABLE tournaments ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- TOURNAMENT PARTICIPANTS TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS tournament_participants (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  tournament_id uuid NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  forfeited boolean DEFAULT false,
  joined_at timestamptz DEFAULT now(),
  UNIQUE(tournament_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_tournament_participants_tournament_id ON tournament_participants(tournament_id);
CREATE INDEX IF NOT EXISTS idx_tournament_participants_user_id ON tournament_participants(user_id);

ALTER TABLE tournament_participants ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- DAILY SUBMISSIONS TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS daily_submissions (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  submission_date date NOT NULL,
  submission_text text NOT NULL,
  wordle_score integer NOT NULL,
  submitted_at timestamptz DEFAULT now(),
  UNIQUE(user_id, submission_date)
);

CREATE INDEX IF NOT EXISTS idx_daily_submissions_user_id ON daily_submissions(user_id);
CREATE INDEX IF NOT EXISTS idx_daily_submissions_date ON daily_submissions(submission_date);

ALTER TABLE daily_submissions ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- TOURNAMENT SCORES TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS tournament_scores (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  tournament_id uuid NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  total_score integer DEFAULT 0,
  last_updated timestamptz DEFAULT now(),
  UNIQUE(tournament_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_tournament_scores_tournament_id ON tournament_scores(tournament_id);
CREATE INDEX IF NOT EXISTS idx_tournament_scores_user_id ON tournament_scores(user_id);

ALTER TABLE tournament_scores ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- RLS POLICIES - TOURNAMENTS
-- ============================================================================

CREATE POLICY "Users can read tournaments they participate in"
  ON tournaments FOR SELECT
  TO authenticated
  USING (
    created_by = auth.uid() OR
    EXISTS (
      SELECT 1 FROM tournament_participants
      WHERE tournament_participants.tournament_id = tournaments.id
      AND tournament_participants.user_id = auth.uid()
    )
  );

CREATE POLICY "Users can create tournaments if they have less than 4"
  ON tournaments FOR INSERT
  TO authenticated
  WITH CHECK (
    auth.uid() = created_by AND
    (SELECT COUNT(*) FROM tournaments WHERE created_by = auth.uid()) < 4
  );

CREATE POLICY "Tournament creators can update their draft tournaments"
  ON tournaments FOR UPDATE
  TO authenticated
  USING (created_by = auth.uid() AND status = 'draft')
  WITH CHECK (created_by = auth.uid());

CREATE POLICY "Tournament creators can delete their draft tournaments"
  ON tournaments FOR DELETE
  TO authenticated
  USING (created_by = auth.uid() AND status = 'draft');

-- ============================================================================
-- RLS POLICIES - TOURNAMENT PARTICIPANTS
-- ============================================================================

CREATE POLICY "Users can read participants in their tournaments"
  ON tournament_participants FOR SELECT
  TO authenticated
  USING (
    user_id = auth.uid() OR
    EXISTS (
      SELECT 1 FROM tournaments
      WHERE tournaments.id = tournament_participants.tournament_id
      AND tournaments.created_by = auth.uid()
    ) OR
    EXISTS (
      SELECT 1 FROM tournament_participants tp2
      WHERE tp2.tournament_id = tournament_participants.tournament_id
      AND tp2.user_id = auth.uid()
    )
  );

CREATE POLICY "Users can join tournaments with valid code and restrictions"
  ON tournament_participants FOR INSERT
  TO authenticated
  WITH CHECK (
    auth.uid() = user_id AND
    -- User has less than 4 active tournaments
    (SELECT COUNT(*) 
     FROM tournament_participants tp 
     JOIN tournaments t ON t.id = tp.tournament_id 
     WHERE tp.user_id = auth.uid() AND t.status IN ('draft', 'active')
    ) < 4 AND
    -- Tournament has less than 15 participants
    (SELECT COUNT(*) 
     FROM tournament_participants 
     WHERE tournament_id = tournament_participants.tournament_id
    ) < 15 AND
    -- Tournament is in draft or active status
    EXISTS (
      SELECT 1 FROM tournaments 
      WHERE id = tournament_participants.tournament_id 
      AND status IN ('draft', 'active')
    )
  );

CREATE POLICY "Users can update their own participation (forfeit)"
  ON tournament_participants FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Tournament creators can remove participants from draft tournaments"
  ON tournament_participants FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM tournaments
      WHERE tournaments.id = tournament_participants.tournament_id
      AND tournaments.created_by = auth.uid()
      AND tournaments.status = 'draft'
    )
  );

-- ============================================================================
-- RLS POLICIES - DAILY SUBMISSIONS
-- ============================================================================

CREATE POLICY "Users can read all submissions"
  ON daily_submissions FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Users can insert their own daily submission"
  ON daily_submissions FOR INSERT
  TO authenticated
  WITH CHECK (
    auth.uid() = user_id AND
    -- Only one submission per day
    NOT EXISTS (
      SELECT 1 FROM daily_submissions
      WHERE user_id = auth.uid() AND submission_date = daily_submissions.submission_date
    )
  );

-- ============================================================================
-- RLS POLICIES - TOURNAMENT SCORES
-- ============================================================================

CREATE POLICY "Users can read tournament scores for their tournaments"
  ON tournament_scores FOR SELECT
  TO authenticated
  USING (
    user_id = auth.uid() OR
    EXISTS (
      SELECT 1 FROM tournament_participants
      WHERE tournament_participants.tournament_id = tournament_scores.tournament_id
      AND tournament_participants.user_id = auth.uid()
    ) OR
    EXISTS (
      SELECT 1 FROM tournaments
      WHERE tournaments.id = tournament_scores.tournament_id
      AND tournaments.created_by = auth.uid()
    )
  );

CREATE POLICY "System can insert tournament scores"
  ON tournament_scores FOR INSERT
  TO authenticated
  WITH CHECK (true);

CREATE POLICY "System can update tournament scores"
  ON tournament_scores FOR UPDATE
  TO authenticated
  USING (true)
  WITH CHECK (true);

-- ============================================================================
-- TRIGGERS AND FUNCTIONS
-- ============================================================================

-- Function to update tournament scores when a submission is made
CREATE OR REPLACE FUNCTION update_tournament_scores_on_submission()
RETURNS TRIGGER AS $$
BEGIN
  -- Update scores for all active tournaments the user is in
  INSERT INTO tournament_scores (tournament_id, user_id, total_score, last_updated)
  SELECT 
    tp.tournament_id,
    NEW.user_id,
    COALESCE(SUM(ds.wordle_score), 0) as total_score,
    now()
  FROM tournament_participants tp
  JOIN tournaments t ON t.id = tp.tournament_id
  LEFT JOIN daily_submissions ds ON ds.user_id = NEW.user_id 
    AND ds.submission_date >= t.start_date 
    AND ds.submission_date <= t.end_date
  WHERE tp.user_id = NEW.user_id
    AND t.status IN ('active', 'closed')
    AND tp.forfeited = false
    AND NEW.submission_date >= t.start_date
    AND NEW.submission_date <= t.end_date
  GROUP BY tp.tournament_id, NEW.user_id
  ON CONFLICT (tournament_id, user_id) 
  DO UPDATE SET 
    total_score = EXCLUDED.total_score,
    last_updated = EXCLUDED.last_updated;
    
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER on_submission_update_scores
  AFTER INSERT ON daily_submissions
  FOR EACH ROW
  EXECUTE FUNCTION update_tournament_scores_on_submission();
