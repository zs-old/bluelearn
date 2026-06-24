-- Add a variant (a method/alternative) under an existing topic: a new draft
-- guide plus its first draft revision. Mirrors create_topic except
-- the guide_base (which already exists) and knowledge_type (inherited from
-- the base).

create or replace function public.create_variant(
  p_guide_base_id uuid,
  p_title text,
  p_summary text default null,
  p_body text default null
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_guide_id uuid := gen_random_uuid();
  v_revision_id uuid := gen_random_uuid();
begin
  -- slug stays NULL until publish like create_topic's first guide.
  insert into public.guides (id, guide_base_id, author_id, status)
    values (v_guide_id, p_guide_base_id, auth.uid(), 'draft');

  insert into public.guide_revisions
    (id, guide_id, revision_number, title, summary, body, author_id, status)
    values (v_revision_id, v_guide_id, 1, p_title, p_summary, p_body, auth.uid(), 'draft');

  -- Return the draft revision id so the client routes straight to its editor.
  return v_revision_id;
end;
$$;

grant execute on function public.create_variant(uuid, text, text, text) to authenticated;
