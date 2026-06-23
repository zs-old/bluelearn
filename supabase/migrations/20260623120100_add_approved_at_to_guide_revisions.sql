-- When a revision is approved to its guide's current_revision_id.
-- A revision can accumulate several review_cases over its life 
-- (dispute, appeal, etc.), so its go-live time can't be
-- cleanly derived from them.

alter table public.guide_revisions
  add column approved_at timestamptz;
