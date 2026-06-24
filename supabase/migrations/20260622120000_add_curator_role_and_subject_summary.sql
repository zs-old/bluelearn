-- Add the curator role (authorizes authoring learning paths) and an optional
-- summary on subjects.
alter type public.app_role add value 'curator' before 'admin';

alter table public.subjects add column summary text;
