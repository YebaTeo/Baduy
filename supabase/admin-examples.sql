-- Execute only from the Supabase SQL Editor / trusted admin environment.
-- Review the media and location with community stakeholders before approving.
select p.id,p.caption,p.latitude,p.longitude,p.location_name,m.storage_path
from public.posts p join public.post_media m on m.post_id=p.id
where p.status='pending' order by p.created_at;

-- Replace the UUID after review; never bulk approve without review.
-- update public.posts set status='approved' where id='REVIEWED_POST_UUID';
-- Remove from feed and future signed media URL issuance:
-- update public.posts set status='removed' where id='POST_UUID';

select r.id,r.reason,r.post_id,r.created_at from public.reports r where r.status='open' order by r.created_at;
-- update public.reports set status='resolved' where id='REPORT_UUID';

-- Add only real, consented guide information. Use SQL Editor table editing or bound
-- parameters from a trusted admin script. contact_information accepts https:, tel:, mailto:.
-- Guide photos go to the PRIVATE guide-images bucket using an administrator session.
-- is_verified=true publishes a profile; the client cannot set it.

-- Replace configurable guidance with locally reviewed text:
-- update public.community_guidance set message='LOCALLY_REVIEWED_MESSAGE' where id=1;

-- Schedule daily to bound rate-limiter storage growth:
delete from private.auth_limits where window_start < now()-interval '1 day';
