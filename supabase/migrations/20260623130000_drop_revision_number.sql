-- Drop revision_number. It was a per-guide / per-path counter meant as a
-- "version N" label, but the published-version history orders by approved_at and
-- "which one is live" is current_revision_id.

alter table public.guide_revisions drop column revision_number;
alter table public.learning_path_revisions drop column revision_number;

-- create_topic and create_variant seeded the first revision with revision_number
-- = 1; recreate them without it. create_topic is also renamed to create_guide to
-- match the resource it creates. Functions are otherwise unchanged from
-- 20260620120200_allow_lazy_topic_creation.sql.

drop function if exists public.create_topic(text, public.knowledge_type, text, text);

create or replace function public.create_guide(
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
    (id, guide_id, title, summary, body, author_id, status)
    values (v_revision_id, v_guide_id, p_title, p_summary, p_body, auth.uid(), 'draft');

  -- Return the draft revision id so the client routes straight to its editor.
  return v_revision_id;
end;
$$;

grant execute on function public.create_guide(
  text, public.knowledge_type, text, text
) to authenticated;

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
    (id, guide_id, title, summary, body, author_id, status)
    values (v_revision_id, v_guide_id, p_title, p_summary, p_body, auth.uid(), 'draft');

  return v_revision_id;
end;
$$;
