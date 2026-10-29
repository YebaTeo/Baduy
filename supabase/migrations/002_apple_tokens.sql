begin;
-- Server-only tokens used exclusively to revoke Apple authorization on account deletion.
create table private.apple_tokens(user_id uuid primary key references auth.users on delete cascade, refresh_token text not null);
create function public.save_apple_token(uid uuid,token text) returns void language sql security definer set search_path='' as $$
 insert into private.apple_tokens values(uid,token) on conflict(user_id) do update set refresh_token=excluded.refresh_token $$;
create function public.get_apple_token(uid uuid) returns text language sql security definer set search_path='' as $$ select refresh_token from private.apple_tokens where user_id=uid $$;
revoke all on function public.save_apple_token(uuid,text),public.get_apple_token(uuid) from public,anon,authenticated;
grant execute on function public.save_apple_token(uuid,text),public.get_apple_token(uuid) to service_role;
commit;
