import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const source = readFileSync(new URL('../../Sources/ZCREBunny/Resources/ReadOutputs.js', import.meta.url), 'utf8');
const run = new (Object.getPrototypeOf(async function(){}).constructor)('window','location','workspaceKey','requestID','fetch', source);
function context() { return {Clerk:{user:{id:'user'}, session:{id:'session',getToken:async()=> 'test-only'},organization:null}}; }
test('outputs: only one GET for chosen job and returns no private inputs',async()=>{
 let calls=0;
 const result=JSON.parse(await run(context(),{origin:'https://www.zcre.co.kr'},'user:personal','req_one',async(path,init)=>{
  calls++; assert.equal(path,'/api/v1/requests/req_one/outputs');assert.equal(init.method,'GET');assert.equal(init.redirect,'error');
  return {ok:true,json:async()=>({outputs:[{output_id:'out',delivery_url:'https://cdn.example.com/a',content_type:'image/png',inputs:'private',prompt:'private'}]})};
 }));
 assert.equal(calls,1);assert.equal(result.outputs.length,1);assert.equal(result.outputs[0].prompt,undefined);assert.equal(result.outputs[0].inputs,undefined);
});
test('outputs: reject account mismatch and path injection before fetch',async()=>{
 for(const [workspace,id] of [['other:personal','req_one'],['user:personal','../balance']]){
  await assert.rejects(run(context(),{origin:'https://www.zcre.co.kr'},workspace,id,()=>{assert.fail('unexpected fetch')}));
 }
});
test('outputs: discard response after session switches',async()=>{
 const win=context();await assert.rejects(run(win,{origin:'https://www.zcre.co.kr'},'user:personal','req_one',async()=>{
 win.Clerk.session.id='new';return {ok:true,json:async()=>({outputs:[]})};
 }));
});
test('outputs: preserve Retry-After and never retry automatically',async()=>{
 let calls=0;const result=JSON.parse(await run(context(),{origin:'https://www.zcre.co.kr'},'user:personal','req_one',async()=>{
 calls++;return {ok:false,status:429,headers:{get:()=> '120'}};
 }));assert.equal(calls,1);assert.equal(result.error,429);assert.equal(result.retryAfter,'120');
});
