-- Publishing a learning path revision is one logical step but four writes across
-- three tables (freeze the revision, freeze the edge projection, point the path
-- at it, freeze the slug on first publish). The write policies forbid users from
-- flipping a path/revision to published directly, so a partial publish can never
-- leave an edge-less or pointer-less live path.
create or replace function public.publish_learning_path_revision(p_revision_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_path_id uuid;
  v_status public.learning_path_revision_status;
  v_author_id uuid;
  v_title text;
  v_slug text;
begin
  if not public.has_role('curator') then
    raise exception 'Only curators can publish learning paths'
      using errcode = 'insufficient_privilege';
  end if;

  select learning_path_id, status, author_id, title
    into v_path_id, v_status, v_author_id, v_title
    from public.learning_path_revisions
    where id = p_revision_id
    for update;

  if not found then
    raise exception 'Revision not found' using errcode = 'no_data_found';
  end if;

  if v_author_id is distinct from (select auth.uid()) then
    raise exception 'You can only publish a revision you authored'
      using errcode = 'insufficient_privilege';
  end if;

  if v_status <> 'draft' then
    raise exception 'Revision is not an editable draft'
      using errcode = 'invalid_parameter_value';
  end if;

  -- On first publish the path has no slug yet; derive and freeze it from the
  -- title, which must be present by then.
  select slug into v_slug from public.learning_paths where id = v_path_id;
  if v_slug is null and coalesce(trim(v_title), '') = '' then
    raise exception 'A title is required to publish a learning path'
      using errcode = 'invalid_parameter_value';
  end if;

  update public.learning_path_revisions
    set status = 'published',
        published_at = now()
    where id = p_revision_id;

  insert into public.learning_path_revision_edges
    (revision_id, from_guide_base_id, to_guide_base_id)
  select p_revision_id, e.from_guide_base_id, e.to_guide_base_id
    from public.project_path_edges(p_revision_id) e;

  update public.learning_paths
    set current_revision_id = p_revision_id,
        status = 'published',
        slug = coalesce(
          slug,
          lower(trim(both '-' from
            regexp_replace(v_title, '[^a-zA-Z0-9]+', '-', 'g')))
        )
    where id = v_path_id
    returning slug into v_slug;

  -- Return the live slug so the client can route to /paths/{slug}.
  return v_slug;
end;
$$;

grant execute on function public.publish_learning_path_revision(uuid) to authenticated;
