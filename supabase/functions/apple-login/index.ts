import {admin,client,response,failure,limit,body} from '../_shared/server.ts';
import {createRemoteJWKSet,jwtVerify} from 'npm:jose@6.1.0';
const keys=createRemoteJWKSet(new URL('https://appleid.apple.com/auth/keys'));
Deno.serve(async req=>{
 if(req.method!=='POST') return response({},405);
 try {
  const {id_token,nonce,code}=await body(req);
  if(typeof id_token!=='string'||typeof nonce!=='string'||typeof code!=='string') throw new Error();
  const clientID=Deno.env.get('APPLE_CLIENT_ID')!;
  const {payload}=await jwtVerify(id_token,keys,{issuer:'https://appleid.apple.com',audience:clientID});
  const digest=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(nonce));
  const hash=Array.from(new Uint8Array(digest)).map(x=>x.toString(16).padStart(2,'0')).join('');
  if(payload.nonce!==hash||!payload.sub) throw new Error();
  await limit(req,`apple:${payload.sub}`);
  const exchange=await fetch('https://appleid.apple.com/auth/token',{method:'POST',body:new URLSearchParams({client_id:clientID,client_secret:Deno.env.get('APPLE_CLIENT_SECRET')!,code,grant_type:'authorization_code'})});
  const tokens=await exchange.json();
  if(!exchange.ok||!tokens.refresh_token||!tokens.id_token) throw new Error();
  const {payload:exchanged}=await jwtVerify(tokens.id_token,keys,{issuer:'https://appleid.apple.com',audience:clientID});
  if(exchanged.sub!==payload.sub) throw new Error();
  const {data,error}=await client().auth.signInWithIdToken({provider:'apple',token:id_token,nonce});
  if(error||!data.session) throw new Error();
  const {error:saveError}=await admin.rpc('save_apple_token',{uid:data.user.id,token:tokens.refresh_token});
  if(saveError) throw saveError;
  return response(data.session);
 } catch { return failure(); }
});
