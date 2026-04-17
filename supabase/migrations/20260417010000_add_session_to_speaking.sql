-- Add session_id and attempt_number to speaking_results so multiple attempts
-- on the same topic can be grouped into a single practice session.

ALTER TABLE public.speaking_results
  ADD COLUMN IF NOT EXISTS session_id TEXT,
  ADD COLUMN IF NOT EXISTS attempt_number INTEGER;

-- Backfill: treat every existing row as a one-attempt session.
UPDATE public.speaking_results
   SET session_id = id,
       attempt_number = 1
 WHERE session_id IS NULL;

-- Helpful index for history-by-session queries.
CREATE INDEX IF NOT EXISTS speaking_results_session_id_idx
  ON public.speaking_results(session_id);
