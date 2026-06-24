-- Learning paths drop their pre-publish review gate for now: a curator's submit
-- publishes directly, with no review_case in between.

drop table if exists public.learning_path_review_cases;
alter type public.case_type rename to case_type_old;

create type public.case_type as enum (
  'guide_publish',
  'guide_edit'
);

alter table public.review_cases
  alter column case_type type public.case_type
  using case_type::text::public.case_type;

drop type public.case_type_old;

-- With no review gate, a learning path revision is either a draft or published.
-- The shared revision_status 'submitted' (= awaiting review) no longer fits.
-- Drop every policy that reads the revision status first so the column type
-- can be swapped, then recreate them below against the new enum.
drop policy if exists "Submitted path revisions are viewable by everyone"
  on public.learning_path_revisions;
drop policy if exists "Curators can create their own draft path revisions"
  on public.learning_path_revisions;
drop policy if exists "Curators can edit and submit their own draft path revisions"
  on public.learning_path_revisions;
drop policy if exists "Path nodes are viewable when their revision is"
  on public.learning_path_revision_nodes;
drop policy if exists "Curators can edit nodes of their own draft revisions"
  on public.learning_path_revision_nodes;
drop policy if exists "Path edges are viewable when their revision is"
  on public.learning_path_revision_edges;

create type public.learning_path_revision_status as enum ('draft', 'published');

alter table public.learning_path_revisions
  alter column status drop default,
  alter column status type public.learning_path_revision_status
    using (case status::text when 'draft' then 'draft' else 'published' end)
      ::public.learning_path_revision_status,
  alter column status set default 'draft';

alter table public.learning_path_revisions
  add column published_at timestamptz;

drop policy if exists "Authenticated users can create draft paths"
  on public.learning_paths;
create policy "Curators can create draft paths"
  on public.learning_paths for insert
  to authenticated
  with check (
    created_by = (select auth.uid())
    and status = 'draft'
    and public.has_role('curator')
  );

drop policy if exists "Curators can update their own paths except publishing"
  on public.learning_paths;
create policy "Curators can update their own paths except publishing"
  on public.learning_paths for update
  to authenticated
  using (created_by = (select auth.uid()) and public.has_role('curator'))
  with check (
    created_by = (select auth.uid())
    and public.has_role('curator')
    and status in ('draft', 'archived')
  );

create policy "Published path revisions are viewable by everyone"
  on public.learning_path_revisions for select
  using (status = 'published' or author_id = (select auth.uid()));

create policy "Curators can create draft path revisions"
  on public.learning_path_revisions for insert
  to authenticated
  with check (
    author_id = (select auth.uid())
    and status = 'draft'
    and public.has_role('curator')
  );

create policy "Curators can edit their own draft path revisions"
  on public.learning_path_revisions for update
  to authenticated
  using (
    author_id = (select auth.uid())
    and status = 'draft'
    and public.has_role('curator')
  )
  with check (
    author_id = (select auth.uid())
    and status = 'draft'
    and public.has_role('curator')
  );

-- learning_path_revision_nodes: nodes are visible when their revision is; a
-- curator edits nodes of any draft revision they authored.
create policy "Path nodes are viewable when their revision is"
  on public.learning_path_revision_nodes for select
  using (
    exists (
      select 1 from public.learning_path_revisions r
      where r.id = revision_id
        and (r.status = 'published' or r.author_id = (select auth.uid()))
    )
  );

create policy "Curators can edit nodes of their own draft revisions"
  on public.learning_path_revision_nodes for all
  to authenticated
  using (
    public.has_role('curator')
    and exists (
      select 1 from public.learning_path_revisions r
      where r.id = revision_id
        and r.author_id = (select auth.uid())
        and r.status = 'draft'
    )
  )
  with check (
    public.has_role('curator')
    and exists (
      select 1 from public.learning_path_revisions r
      where r.id = revision_id
        and r.author_id = (select auth.uid())
        and r.status = 'draft'
    )
  );

-- learning_path_revision_edges: visible when their revision is. Rows are written
-- only by the publish RPC, never by users, so there is no write policy.
create policy "Path edges are viewable when their revision is"
  on public.learning_path_revision_edges for select
  using (
    exists (
      select 1 from public.learning_path_revisions r
      where r.id = revision_id
        and (r.status = 'published' or r.author_id = (select auth.uid()))
    )
  );
