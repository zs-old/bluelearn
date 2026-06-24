-- Lazy topic creation. A topic now starts as an empty draft and is fleshed
-- out in the editor (the client navigates to the editor first and persists on the
-- first autosave). So, creation no longer requires a title or a slug.

alter table public.guide_bases alter column slug drop not null;
alter table public.guide_bases alter column title drop not null;
drop function if exists public.create_topic(text, text, public.knowledge_type, text, text);

create or replace function public.create_topic(
  p_title text default null,
  p_knowledge_type public.knowledge_type default 'theory',
  p_summary text default null,
  p_body text default null
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_base_id uuid := gen_random_uuid();
  v_guide_id uuid := gen_random_uuid();
  v_revision_id uuid := gen_random_uuid();
begin
  -- knowledge_type defaults to theory and is changeable
  -- in the editor while the topic is a draft.
  insert into public.guide_bases (id, knowledge_type, status)
    values (v_base_id, p_knowledge_type, 'draft');

  insert into public.guides (id, guide_base_id, author_id, status)
    values (v_guide_id, v_base_id, auth.uid(), 'draft');

  insert into public.guide_revisions
    (id, guide_id, revision_number, title, summary, body, author_id, status)
    values (v_revision_id, v_guide_id, 1, p_title, p_summary, p_body, auth.uid(), 'draft');

  -- Return the draft revision id so the client routes straight to its editor.
  return v_revision_id;
end;
$$;

grant execute on function public.create_topic(
  text, public.knowledge_type, text, text
) to authenticated;

-- Variants are lazily created the same way: content is optional
--  at creation and filled in the editor.
create or replace function public.create_variant(
  p_guide_base_id uuid,
  p_title text default null,
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
  insert into public.guides (id, guide_base_id, author_id, status)
    values (v_guide_id, p_guide_base_id, auth.uid(), 'draft');

  insert into public.guide_revisions
    (id, guide_id, revision_number, title, summary, body, author_id, status)
    values (v_revision_id, v_guide_id, 1, p_title, p_summary, p_body, auth.uid(), 'draft');

  return v_revision_id;
end;
$$;

grant execute on function public.create_variant(uuid, text, text, text) to authenticated;
