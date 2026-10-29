import { createClient } from 'npm:@supabase/supabase-js@2.57.4';
export const url = Deno.env.get('SUPABASE_URL')!;
export const anon = Deno.env.get('SUPABASE_ANON_KEY')!;
export const admin = createClient(url,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
export const client = () => createClient(url,anon,{auth:{persistSession:false,autoRefreshToken:false}});
export const response = (body:unknown,status=200) => new Response(JSON.stringify(body),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store'}});
export const failure = () => response({message:'Unable to complete authentication. Check your details or try again later.'},400);
export async function limit(req:Request,identity:string) {
 const ip=req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() || 'unknown';
 for(const value of [`ip:${ip}`,`identity:${identity}`]) {
  const digest=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(value));
  const bucket=Array.from(new Uint8Array(digest)).map(x=>x.toString(16).padStart(2,'0')).join('');
  const {data,error}=await admin.rpc('auth_limit',{bucket,max_attempts:value.startsWith('ip:')?30:10});
  if(error || !data) throw new Error('Rate limit');
 }
}

// Bound bodies independently of Content-Length (which may be absent or forged).
export async function body(req:Request):Promise<Record<string,unknown>> {
 const reader=req.body?.getReader(); if(!reader) throw new Error();
 let size=0; const chunks:Uint8Array[]=[];
 try {
  while(true){ const {value,done}=await reader.read(); if(done) break;
   size+=value.length; if(size>8192){await reader.cancel();throw new Error();} chunks.push(value);
  }
 } finally {reader.releaseLock();}
 const bytes=new Uint8Array(size); let offset=0;
 for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
 const parsed=JSON.parse(new TextDecoder().decode(bytes));
 if(!parsed||typeof parsed!=='object'||Array.isArray(parsed)) throw new Error();
 return parsed;
}
