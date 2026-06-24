-- create_learning_path seeds a new draft (learning path shell + revision 1) in
-- one transaction, mirroring create_guide. project_path_edges computes the
-- prerequisite edges among a revision's included nodes by projecting the global
-- guide_edges graph onto that node set, bridging excluded (skipped) prereqs. The
-- draft read path calls project_path_edges live, whereas publish calls it once and
-- freezes the result into learning_path_revision_edges.

create or replace function public.create_learning_path(
  p_targets uuid[],
  p_title text default null,
  p_summary text default null
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_path_id uuid := gen_random_uuid();
  v_revision_id uuid := gen_random_uuid();
begin
  if p_targets is null or array_length(p_targets, 1) is null then
    raise exception 'At least one target guide base is required'
      using errcode = 'invalid_parameter_value';
  end if;

  insert into public.learning_paths (id, created_by, status)
    values (v_path_id, auth.uid(), 'draft');

  insert into public.learning_path_revisions
    (id, learning_path_id, title, summary, author_id, status)
    values (v_revision_id, v_path_id, p_title, p_summary, auth.uid(), 'draft');

  -- closure: the targets plus every transitive prerequisite, walking guide_edges
  -- backward (from a known node to its prerequisites). Each node is seeded as a
  -- membership row through its base's canonical variant; the targets are flagged.
  insert into public.learning_path_revision_nodes
    (revision_id, guide_base_id, guide_id, is_target)
  with recursive closure as (
    select unnest(p_targets) as node_id
    union
    select e.from_guide_base_id
    from closure c
    join public.guide_edges e
      on e.to_guide_base_id = c.node_id
     and e.edge_type = 'prerequisite'
     and not e.is_suspended
  )
  select
    v_revision_id,
    gb.id,
    gb.canonical_guide_id,
    gb.id = any (p_targets)
  from closure c
  join public.guide_bases gb on gb.id = c.node_id;

  -- Return the draft revision id so the client routes straight to its editor.
  return v_revision_id;
end;
$$;

grant execute on function public.create_learning_path(uuid[], text, text)
  to authenticated;

-- Project guide_edges onto a revision's included nodes. The walk
-- starts at each included node and recurses backward only through excluded
-- intermediates, so a skipped prereq (A -> Trig -> B with Trig excluded) bridges
-- to A -> B.
create or replace function public.project_path_edges(p_revision_id uuid)
returns table (from_guide_base_id uuid, to_guide_base_id uuid)
language sql
security invoker
set search_path = ''
stable
as $$
  with recursive
  included as (
    select guide_base_id
    from public.learning_path_revision_nodes
    where revision_id = p_revision_id
  ),
  -- anchor = the included node we are finding prerequisites for; cur = the node
  -- reached walking backward from it.
  walk as (
    select n.guide_base_id as anchor, e.from_guide_base_id as cur
    from included n
    join public.guide_edges e
      on e.to_guide_base_id = n.guide_base_id
     and e.edge_type = 'prerequisite'
     and not e.is_suspended
    union
    select w.anchor, e.from_guide_base_id
    from walk w
    join public.guide_edges e
      on e.to_guide_base_id = w.cur
     and e.edge_type = 'prerequisite'
     and not e.is_suspended
    where w.cur not in (select guide_base_id from included)
  )
  select distinct cur as from_guide_base_id, anchor as to_guide_base_id
  from walk
  where cur in (select guide_base_id from included);
$$;

grant execute on function public.project_path_edges(uuid) to authenticated;
