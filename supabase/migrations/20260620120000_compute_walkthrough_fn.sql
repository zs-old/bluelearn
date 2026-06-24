-- Materialize a topic's transitive prerequisite DAG: every guide base that must
-- be understood before the target, plus the prerequisite edges among them.

create or replace function public.compute_walkthrough(p_guide_base_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
stable
as $$
  -- closure c: the target plus every transitive prerequisite, each tagged with a
  -- path depth.
  with recursive closure as (
    -- The target sits at the bottom of its own walkthrough.
    select p_guide_base_id as node_id, 0 as depth
    union
    -- e = guide_edge: walk one hop back to a prerequisite of a known node.
    select e.from_guide_base_id, c.depth + 1
    from closure c
    join public.guide_edges e
      on e.to_guide_base_id = c.node_id
     and e.edge_type = 'prerequisite'
     and not e.is_suspended
  ),
  -- Taking max(depth) ensures each node settles at its longest
  -- prerequisite chain. nd = node_depth.
  node_depth as (
    select node_id, max(depth) as depth
    from closure
    group by node_id
  ),
  -- Named 'visible' because RLS drops nodes the calling user
  -- doesn't have permission to see. gb = guide_base (title),
  -- cg = canonical guide, cr = canonical revision.
  visible_nodes as (
    select nd.node_id, nd.depth, gb.slug, gb.title, cr.summary
    from node_depth nd
    join public.guide_bases gb on gb.id = nd.node_id
    left join public.guides cg on cg.id = gb.canonical_guide_id
    left join public.guide_revisions cr on cr.id = cg.current_revision_id
  ),
  -- visible_edges: prerequisite edges whose endpoints both survived RLS, so we
  -- never return an edge pointing at a node we filtered away.
  visible_edges as (
    select e.from_guide_base_id as from_id, e.to_guide_base_id as to_id
    from public.guide_edges e
    where e.edge_type = 'prerequisite'
      and not e.is_suspended
      and e.from_guide_base_id in (select node_id from visible_nodes)
      and e.to_guide_base_id in (select node_id from visible_nodes)
  )
  select jsonb_build_object(
    'nodes', coalesce(
      (select jsonb_agg(
        jsonb_build_object(
          'id', node_id,
          'slug', slug,
          'title', title,
          'summary', summary,
          'depth', depth
        )
        order by depth, slug
      ) from visible_nodes),
      '[]'::jsonb
    ),
    'edges', coalesce(
      (select jsonb_agg(
        jsonb_build_object('from_id', from_id, 'to_id', to_id)
      ) from visible_edges),
      '[]'::jsonb
    )
  );
$$;

grant execute on function public.compute_walkthrough(uuid) to anon, authenticated;
