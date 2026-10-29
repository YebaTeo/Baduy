import {admin,client,response,failure,limit,body} from '../_shared/server.ts';
Deno.serve(async req=>{
 if(req.method!=='POST') return response({},405);
 const started=Date.now();
 try {
  if(Number(req.headers.get('content-length')||0)>8192) throw new Error();
  const {username,password}=await body(req);
  if(typeof username!=='string'||typeof password!=='string'||password.length>256) throw new Error();
  const handle=username.trim().toLowerCase();
  if(!/^[a-z0-9_]{3,24}$/.test(handle)) throw new Error();
  await limit(req,handle);
  const {data:email,error}=await admin.rpc('login_email',{handle});
  if(error) throw error;
  // Always invoke Auth, including unknown usernames; never return an email mapping.
  const {data,error:authError}=await client().auth.signInWithPassword({email:email||'unknown@invalid.invalid',password});
  if(authError||!data.session) throw new Error();
  return response(data.session);
 } catch {
  await new Promise(r=>setTimeout(r,Math.max(0,700-Date.now())));
  return failure();
 }
});
