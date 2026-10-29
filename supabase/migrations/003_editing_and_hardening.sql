begin;
-- Disallow partial/null coordinate pairs explicitly (SQL CHECK accepts UNKNOWN).
alter table public.posts add constraint complete_location check (
 (latitude is null and longitude is null and location_precision='none') or
 (latitude is not null and longitude is not null and location_precision='approximate')
);
create function public.edit_post(post_id uuid,caption_text text) returns void
 language plpgsql security definer set search_path='' as $$
begin
 update public.posts set caption=caption_text,status='pending' where id=post_id and author_id=auth.uid() and status<>'removed';
 if not found then raise exception 'Post unavailable'; end if;
end $$;
create function public.my_posts_page(before_date timestamptz default null,before_id uuid default null) returns setof public.feed
 language sql stable security invoker set search_path='' as $$
 select * from public.feed where author_id=auth.uid() and (before_date is null or (created_at,id)<(before_date,before_id)) order by created_at desc,id desc limit 15 $$;
revoke all on function public.edit_post(uuid,text),public.my_posts_page(timestamptz,uuid) from public;
grant execute on function public.edit_post(uuid,text),public.my_posts_page(timestamptz,uuid) to authenticated;
-- Prevent concurrent cross-provider identity inserts from passing the guard together.
create or replace function private.no_cross_provider_link() returns trigger language plpgsql security definer set search_path='' as $$
begin
 perform pg_advisory_xact_lock(hashtextextended(new.user_id::text,0));
 if exists(select 1 from auth.identities where user_id=new.user_id and provider<>new.provider) then
  raise exception 'Explicit account linking is not supported';
 end if;
 return new;
end $$;
-- Upload privileges end when a profile has been deleted.
drop policy media_upload on storage.objects;
create policy media_upload on storage.objects for insert to authenticated with check(
 bucket_id='post-media' and (storage.foldername(name))[1]=auth.uid()::text
 and exists(select 1 from public.profiles where id=auth.uid())
);
commit;
