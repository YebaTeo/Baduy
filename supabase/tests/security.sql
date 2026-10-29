-- Run only against an isolated migrated Supabase test project. All fixtures roll back.
\set ON_ERROR_STOP on
begin;
insert into auth.users(id,email,raw_user_meta_data) values
 ('10000000-0000-0000-0000-000000000001','fixture-a@example.invalid','{"username":"fixture_a"}'),
 ('10000000-0000-0000-0000-000000000002','fixture-b@example.invalid','{"username":"fixture_b"}');
do $$ begin
 begin
  insert into auth.users(id,email,raw_user_meta_data) values('10000000-0000-0000-0000-000000000003','fixture-c@example.invalid','{"username":"FIXTURE_A"}');
  raise exception 'FAIL: duplicate case-insensitive username accepted';
 exception when unique_violation then null; end;
end $$;
insert into public.posts(id,author_id,status,caption) values
 ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','approved','Approved fixture'),
 ('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002','pending','Private fixture');
insert into public.post_media(post_id,storage_path,media_type) values
 ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001/fixture.jpg','photo'),
 ('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002/fixture.jpg','photo');
do $$ begin
 begin
  insert into public.posts(author_id,latitude,location_precision) values('10000000-0000-0000-0000-000000000001',-6.60,'approximate');
  raise exception 'FAIL: partial coordinates accepted';
 exception when check_violation then null; end;
 begin
  insert into public.posts(author_id,latitude,longitude,location_precision) values('10000000-0000-0000-0000-000000000001',-6.60123,106.25,'approximate');
  raise exception 'FAIL: precise coordinates accepted';
 exception when check_violation then null; end;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
do $$ begin
 if (select count(*) from public.feed)<>1 then raise exception 'FAIL: pending post leaked'; end if;
 if (select count(*) from public.feed_page())<>1 then raise exception 'FAIL: feed page visibility'; end if;
 begin
  perform public.login_email('fixture_b');
  raise exception 'FAIL: identity mapping callable by client';
 exception when insufficient_privilege then null; end;
 begin
  perform public.get_apple_token('10000000-0000-0000-0000-000000000002');
  raise exception 'FAIL: Apple token callable by client';
 exception when insufficient_privilege then null; end;
 begin
  insert into public.votes(user_id,post_id,vote_type) values('10000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000001',1);
  raise exception 'FAIL: impersonated vote';
 exception when insufficient_privilege then null; end;
 begin
  update public.posts set status='approved' where id='20000000-0000-0000-0000-000000000002';
  raise exception 'FAIL: client can moderate';
 exception when insufficient_privilege then null; end;
 begin
  insert into public.tour_guides(name,description,is_verified) values('Fixture','Fixture',true);
  raise exception 'FAIL: client can impersonate guide';
 exception when insufficient_privilege then null; end;
 begin
  perform 1 from public.reports;
  raise exception 'FAIL: reports publicly readable';
 exception when insufficient_privilege then null; end;
end $$;
insert into public.votes values('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001',1,now());
do $$ begin
 begin
  insert into public.votes values('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001',-1,now());
  raise exception 'FAIL: duplicate vote';
 exception when unique_violation then null; end;
 if (select upvotes from public.feed limit 1)<>1 then raise exception 'FAIL: upvote aggregation'; end if;
end $$;
update public.votes set vote_type=-1 where post_id='20000000-0000-0000-0000-000000000001';
do $$ begin
 if (select upvotes from public.feed limit 1)<>0 or (select downvotes from public.feed limit 1)<>1 then raise exception 'FAIL: switch aggregation'; end if;
end $$;
select public.edit_post('20000000-0000-0000-0000-000000000001','Edited fixture');
do $$ begin
 if (select count(*) from public.feed_page())<>0 then raise exception 'FAIL: edited post remained public'; end if;
 if (select count(*) from public.my_posts_page())<>1 then raise exception 'FAIL: owner cannot see pending post'; end if;
end $$;
reset role;
-- Identity linking guard is exercised independently of the public client.
insert into auth.identities(id,user_id,provider_id,provider,identity_data) values
 ('30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','fixture-email','email','{"sub":"fixture-email"}');
do $$ begin
 begin
  insert into auth.identities(id,user_id,provider_id,provider,identity_data) values
   ('30000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','fixture-apple','apple','{"sub":"fixture-apple"}');
  raise exception 'FAIL: implicit provider linking accepted';
 exception when raise_exception then
  if SQLERRM<>'Explicit account linking is not supported' then raise; end if;
 end;
end $$;
rollback;
\echo 'Security assertions passed (rolled back)'
