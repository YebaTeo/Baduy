begin;
create extension if not exists postgis with schema extensions;
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
create table public.profiles (
 id uuid primary key references auth.users on delete cascade,
 username text unique check (username ~ '^[a-z0-9_]{3,24}$'),
 display_name text check(length(display_name)<=80), avatar_url text,
 created_at timestamptz not null default now()
);
create unique index profiles_username_ci on public.profiles(lower(username));
create function private.new_profile() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.profiles(id,username) values(new.id,lower(nullif(new.raw_user_meta_data->>'username','')));
 return new;
end $$;
create trigger new_profile after insert on auth.users for each row execute function private.new_profile();
-- Prevent implicit email-based linking even if a client bypasses the Edge Function.
create function private.no_cross_provider_link() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from auth.identities where user_id=new.user_id and provider<>new.provider) then
  raise exception 'Explicit account linking is not supported';
 end if;
 return new;
end $$;
create trigger no_cross_provider_link before insert on auth.identities for each row execute function private.no_cross_provider_link();
create table public.posts (
 id uuid primary key default gen_random_uuid(), author_id uuid not null references public.profiles on delete cascade,
 caption text not null default '' check(length(caption)<=2200), categories text[] not null default '{}',
 latitude double precision, longitude double precision, location_name text,
 location_precision text not null default 'none' check(location_precision in ('none','approximate')),
 status text not null default 'pending' check(status in ('pending','approved','removed')),
 created_at timestamptz not null default now(),
 check ((latitude is null and longitude is null and location_precision='none') or
 (latitude between -90 and 90 and longitude between -180 and 180 and location_precision='approximate'
 and latitude=round(latitude::numeric,2)::float8 and longitude=round(longitude::numeric,2)::float8))
);
create index posts_cursor on public.posts(created_at desc,id desc) where status='approved';
create index posts_geo on public.posts using gist (extensions.st_setsrid(extensions.st_makepoint(longitude,latitude),4326)) where latitude is not null;
create table public.post_media (
 id uuid primary key default gen_random_uuid(), post_id uuid not null unique references public.posts on delete cascade,
 storage_path text not null unique, media_type text not null check(media_type in ('photo','video')),
 thumbnail_path text, sort_order int not null default 0
);
create table public.votes (
 user_id uuid not null references public.profiles on delete cascade, post_id uuid not null references public.posts on delete cascade,
 vote_type smallint not null check(vote_type in(-1,1)), created_at timestamptz not null default now(), primary key(user_id,post_id)
);
create index votes_post on public.votes(post_id,vote_type);
create table public.tour_guides (
 id uuid primary key default gen_random_uuid(), name text not null, profile_image_path text,
 description text not null, languages text[] not null default '{}', covered_areas text[] not null default '{}',
 tour_information text, price text, contact_information text, is_verified boolean not null default false,
 created_at timestamptz not null default now()
);
create table public.reports (
 id uuid primary key default gen_random_uuid(), reporter_id uuid not null references public.profiles on delete cascade,
 post_id uuid not null references public.posts on delete cascade, reason text not null check(length(reason) between 3 and 1000),
 status text not null default 'open' check(status in ('open','reviewed','resolved')), created_at timestamptz not null default now(),
 unique(reporter_id,post_id)
);
create table public.community_guidance (id int primary key check(id=1), message text not null);
insert into public.community_guidance values(1,'Ask permission before photographing people or places. Follow locally communicated rules. Do not share sensitive locations.');
alter table public.profiles enable row level security;
alter table public.posts enable row level security;
alter table public.post_media enable row level security;
alter table public.votes enable row level security;
alter table public.tour_guides enable row level security;
alter table public.reports enable row level security;
alter table public.community_guidance enable row level security;
create policy profiles_read on public.profiles for select to authenticated using(true);
create policy profiles_update on public.profiles for update to authenticated using(id=auth.uid()) with check(id=auth.uid());
create policy posts_read on public.posts for select to authenticated using(status='approved' or author_id=auth.uid());
create policy posts_insert on public.posts for insert to authenticated with check(author_id=auth.uid() and status='pending');
create policy posts_delete on public.posts for delete to authenticated using(author_id=auth.uid());
create policy media_read on public.post_media for select to authenticated using(exists(select 1 from public.posts p where p.id=post_id));
create policy votes_read on public.votes for select to authenticated using(exists(select 1 from public.posts p where p.id=post_id and p.status='approved'));
create policy votes_insert on public.votes for insert to authenticated with check(user_id=auth.uid() and exists(select 1 from public.posts p where p.id=post_id and p.status='approved'));
create policy votes_update on public.votes for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid() and exists(select 1 from public.posts p where p.id=post_id and p.status='approved'));
create policy votes_delete on public.votes for delete to authenticated using(user_id=auth.uid());
create policy guides_read on public.tour_guides for select to authenticated using(is_verified);
create policy guidance_read on public.community_guidance for select to authenticated using(true);
create policy reports_insert on public.reports for insert to authenticated with check(reporter_id=auth.uid() and status='open');
revoke all on public.profiles,public.posts,public.post_media,public.votes,public.tour_guides,public.reports,public.community_guidance from anon,authenticated;
grant select on public.profiles,public.posts,public.post_media,public.votes,public.tour_guides,public.community_guidance to authenticated;
grant update(username,display_name,avatar_url) on public.profiles to authenticated;
grant delete on public.posts to authenticated;
grant insert,update,delete on public.votes to authenticated;
grant insert(reporter_id,post_id,reason) on public.reports to authenticated;
-- Moderation and guide edits use service-role only, from a trusted administrative environment.
create view public.feed with(security_invoker=true) as
 select p.*,pr.username,m.storage_path,m.media_type,m.thumbnail_path,
 (select count(*) from public.votes v where v.post_id=p.id and v.vote_type=1) as upvotes,
 (select count(*) from public.votes v where v.post_id=p.id and v.vote_type=-1) as downvotes,
 coalesce((select v.vote_type from public.votes v where v.post_id=p.id and v.user_id=auth.uid()),0) as my_vote
 from public.posts p join public.profiles pr on pr.id=p.author_id join public.post_media m on m.post_id=p.id;
grant select on public.feed to authenticated;
create function public.feed_page(before_date timestamptz default null,before_id uuid default null) returns setof public.feed
 language sql stable security invoker set search_path='' as $$
 select * from public.feed where status='approved' and (before_date is null or (created_at,id)<(before_date,before_id)) order by created_at desc,id desc limit 15 $$;
create function public.map_posts(south float8,west float8,north float8,east float8) returns setof public.feed
 language sql stable security invoker set search_path='' as $$
 select * from public.feed where status='approved' and latitude is not null
 and extensions.st_intersects(extensions.st_setsrid(extensions.st_makepoint(longitude,latitude),4326),extensions.st_makeenvelope(west,south,east,north,4326))
 order by created_at desc,id desc limit 150 $$;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
 ('post-media','post-media',false,26214400,array['image/jpeg','video/mp4','video/quicktime']),
 ('guide-images','guide-images',false,5242880,array['image/jpeg','image/png']) on conflict do nothing;
create policy media_upload on storage.objects for insert to authenticated with check(bucket_id='post-media' and (storage.foldername(name))[1]=auth.uid()::text);
create policy media_download on storage.objects for select to authenticated using(
 (bucket_id='post-media' and ((storage.foldername(name))[1]=auth.uid()::text or exists(select 1 from public.post_media m join public.posts p on p.id=m.post_id where (m.storage_path=name or m.thumbnail_path=name) and p.status='approved')))
 or (bucket_id='guide-images' and exists(select 1 from public.tour_guides g where g.is_verified and g.profile_image_path=name)));
create policy media_delete on storage.objects for delete to authenticated using(bucket_id='post-media' and (storage.foldername(name))[1]=auth.uid()::text);
-- Atomic metadata publication: the object must exist and belong to the caller.
create function public.publish_post(post_id uuid,caption_text text,category_list text[],object_path text,kind text,lat float8 default null,lon float8 default null,place text default null,thumb text default null) returns uuid
 language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or split_part(object_path,'/',1)<>auth.uid()::text or not exists(select 1 from storage.objects where bucket_id='post-media' and name=object_path) then raise exception 'Invalid media'; end if;
 if thumb is not null and (split_part(thumb,'/',1)<>auth.uid()::text or not exists(select 1 from storage.objects where bucket_id='post-media' and name=thumb)) then raise exception 'Invalid thumbnail'; end if;
 if cardinality(category_list)>5 then raise exception 'Too many categories'; end if;
 if exists(select 1 from public.posts where id=post_id and author_id=auth.uid()) then return post_id; end if;
 insert into public.posts(id,author_id,caption,categories,latitude,longitude,location_name,location_precision)
 values(post_id,auth.uid(),caption_text,category_list,round(lat::numeric,2),round(lon::numeric,2),place,case when lat is null then 'none' else 'approximate' end);
 insert into public.post_media(post_id,storage_path,media_type,thumbnail_path) values(post_id,object_path,kind,thumb);
 return post_id;
end $$;
revoke all on function public.publish_post(uuid,text,text[],text,text,float8,float8,text,text),public.feed_page(timestamptz,uuid),public.map_posts(float8,float8,float8,float8) from public;
grant execute on function public.publish_post(uuid,text,text[],text,text,float8,float8,text,text),public.feed_page(timestamptz,uuid),public.map_posts(float8,float8,float8,float8) to authenticated;
-- Server-only identity lookup and atomic fixed-window rate limiter.
create table private.auth_limits(key text primary key, window_start timestamptz not null, attempts int not null);
create function public.auth_limit(bucket text,max_attempts int default 10) returns boolean language plpgsql security definer set search_path='' as $$
declare n int;
begin
 insert into private.auth_limits values(bucket,now(),1) on conflict(key) do update set
 attempts=case when private.auth_limits.window_start<now()-interval '15 minutes' then 1 else private.auth_limits.attempts+1 end,
 window_start=case when private.auth_limits.window_start<now()-interval '15 minutes' then now() else private.auth_limits.window_start end returning attempts into n;
 return n<=max_attempts;
end $$;
create function public.login_email(handle text) returns text language sql stable security definer set search_path='' as $$
 select u.email from auth.users u join public.profiles p on p.id=u.id where p.username=lower(handle) and exists(select 1 from auth.identities i where i.user_id=u.id and i.provider='email') $$;
revoke all on function public.auth_limit(text,int),public.login_email(text) from public,anon,authenticated;
grant execute on function public.auth_limit(text,int),public.login_email(text) to service_role;
commit;
