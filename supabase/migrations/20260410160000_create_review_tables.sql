-- review_cards: mutable FSRS card state, upsert on conflict by id
CREATE TABLE review_cards (
  id UUID PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) NOT NULL,
  entry_id INTEGER NOT NULL,
  headword TEXT NOT NULL,
  pos TEXT DEFAULT '',
  due TIMESTAMPTZ NOT NULL,
  stability DOUBLE PRECISION DEFAULT 0,
  difficulty DOUBLE PRECISION DEFAULT 0,
  elapsed_days INTEGER DEFAULT 0,
  scheduled_days INTEGER DEFAULT 0,
  reps INTEGER DEFAULT 0,
  lapses INTEGER DEFAULT 0,
  state INTEGER DEFAULT 0,
  step INTEGER,
  last_review TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_review_cards_user ON review_cards(user_id, updated_at DESC);

ALTER TABLE review_cards ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users_own_data" ON review_cards
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- review_logs: append-only audit trail of each review action
CREATE TABLE review_logs (
  id UUID PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) NOT NULL,
  card_id UUID NOT NULL,
  rating INTEGER NOT NULL,
  state INTEGER NOT NULL,
  due TIMESTAMPTZ NOT NULL,
  stability DOUBLE PRECISION NOT NULL,
  difficulty DOUBLE PRECISION NOT NULL,
  elapsed_days INTEGER NOT NULL,
  scheduled_days INTEGER NOT NULL,
  review_duration INTEGER,
  reviewed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_review_logs_user ON review_logs(user_id, reviewed_at DESC);

ALTER TABLE review_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users_own_data" ON review_logs
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
