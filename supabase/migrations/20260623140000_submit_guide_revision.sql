-- Submitting a draft is one logical step but three writes (flip the revision to
-- submitted, open a review case, link the case to the revision). Wrapping them
-- in a SECURITY INVOKER function keeps them in one transaction so a partial
-- submit can never leave a submitted revision with no case.
create or replace function public.submit_guide_revision(p_revision_id uuid)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_guide_id uuid;
  v_current_revision_id uuid;
  v_case_type public.case_type;
  v_case_id uuid;
begin
  -- RLS confines this to the caller's own draft; zero rows means the revision is
  -- missing, not theirs, or already submitted.
  update public.guide_revisions
    set status = 'submitted'
    where id = p_revision_id
    returning guide_id into v_guide_id;

  if not found then
    raise exception 'Revision not found or not an editable draft'
      using errcode = 'no_data_found';
  end if;

  -- A guide with no live revision yet is the first publish; otherwise, it is an edit.
  select current_revision_id into v_current_revision_id
    from public.guides where id = v_guide_id;

  v_case_type := case
    when v_current_revision_id is null then 'guide_publish'
    else 'guide_edit'
  end;

  insert into public.review_cases (case_type, created_by)
    values (v_case_type, auth.uid())
    returning id into v_case_id;

  insert into public.guide_review_cases (case_id, guide_revision_id)
    values (v_case_id, p_revision_id);

  return v_case_id;
end;
$$;

grant execute on function public.submit_guide_revision(uuid) to authenticated;
