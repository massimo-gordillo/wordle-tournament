/*
  # Tournament chat (pull-based, no realtime)

  - tournament_chat: messages and automated result rows per tournament
  - RLS: only participants of active/closed tournaments can SELECT or INSERT; no UPDATE/DELETE
*/

CREATE TABLE IF NOT EXISTS tournament_chat (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id uuid NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  message text NOT NULL,
  message_type text NOT NULL CHECK (message_type IN ('chat', 'result')),
  submission_date date,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT tournament_chat_message_len CHECK (char_length(message) <= 400),
  CONSTRAINT tournament_chat_submission_date_matches_type CHECK (
    (message_type = 'chat' AND submission_date IS NULL)
    OR (message_type = 'result' AND submission_date IS NOT NULL)
  )
);

CREATE INDEX IF NOT EXISTS idx_tournament_chat_tournament_created
  ON tournament_chat(tournament_id, created_at);

ALTER TABLE tournament_chat ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Participants can read chat in active or closed tournaments"
  ON tournament_chat
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM tournament_participants tp
      JOIN tournaments t ON t.id = tp.tournament_id
      WHERE tp.tournament_id = tournament_chat.tournament_id
        AND tp.user_id = auth.uid()
        AND t.status IN ('active', 'closed')
    )
  );

CREATE POLICY "Participants can insert chat in active or closed tournaments"
  ON tournament_chat
  FOR INSERT
  TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (
      SELECT 1
      FROM tournament_participants tp
      JOIN tournaments t ON t.id = tp.tournament_id
      WHERE tp.tournament_id = tournament_chat.tournament_id
        AND tp.user_id = auth.uid()
        AND t.status IN ('active', 'closed')
    )
  );
