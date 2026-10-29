import {admin,response,failure} from '../_shared/server.ts';
Deno.serve(async req=>{
 if(req.method!=='POST') return response({},405);
 try {
  const jwt=req.headers.get('authorization')?.replace(/^Bearer /,'');
  if(!jwt) return response({},401);
  const {data:{user},error}=await admin.auth.getUser(jwt);
  if(error||!user) return response({},401);
  const {data:token,error:tokenError}=await admin.rpc('get_apple_token',{uid:user.id});
  if(tokenError) throw tokenError;
  if(token){
   const revoked=await fetch('https://appleid.apple.com/auth/revoke',{method:'POST',body:new URLSearchParams({client_id:Deno.env.get('APPLE_CLIENT_ID')!,client_secret:Deno.env.get('APPLE_CLIENT_SECRET')!,token,token_type_hint:'refresh_token'})});
   if(!revoked.ok) throw new Error();
  }
  // Paths are flat under the user's UUID; repeat from offset zero after each removal.
  while(true){
   const {data:files,error:listError}=await admin.storage.from('post-media').list(user.id,{limit:100});
   if(listError) throw listError;
   if(!files?.length) break;
   const {error:removeError}=await admin.storage.from('post-media').remove(files.map(f=>`${user.id}/${f.name}`));
   if(removeError) throw removeError;
  }
  const {error:deleteError}=await admin.auth.admin.deleteUser(user.id);
  if(deleteError) throw deleteError;
  return response({deleted:true});
 } catch {return failure();}
});
