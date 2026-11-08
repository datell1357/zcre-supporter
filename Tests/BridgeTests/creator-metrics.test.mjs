// 요약 API 호출 수·데이터 최소화·세션 경계 검증. 실제 계정과 서버를 사용하지 않는다.
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';
const source = readFileSync(new URL('../../Sources/ZCREBunny/Resources/ReadCreatorMetrics.js', import.meta.url), 'utf8');
const payload = () => ({ total_followers: 100, total_followers_change_7d: null, updated_at: '2026-11-08T00:00:00Z',
    verification_code: 'secret', registered_at: 'private', accounts: [{ account_id: 'internal', platform: 'instagram', handle: 'example',
    followers: 100, followers_change_7d: -2, last_observed_at: '2026-11-08T00:00:00Z', collection_status: 'ok',
    derived_metrics_available: true, verification_code: 'secret', avatar_url: 'private', recent: {posts: ['private']} }] });
async function run({body = payload(), status = 200, contentType = 'application/json', changeSession = false, large = false, workspace = 'user:personal', token = 'local-test', detailStatus = 200, detail = null} = {}) {
    const requests = [];
    const clerk = {user: {id:'user'}, session:{id:'session',getToken:async()=>token}};
    const context = {window:{Clerk:clerk},location:{origin:'https://www.zcre.co.kr'},AbortController,TextDecoder,Uint8Array,setTimeout,clearTimeout,
        fetch: async (url, options) => {
            requests.push({url,options});
            if(changeSession)clerk.user.id='another-user';
            const isDetail = url.includes('/accounts/');
            const value = isDetail ? (detail ?? {account: body.accounts[0], daily:[{day:'2026-11-08',followers:100}], posts:['private']}) : body;
            return new Response(large ? 'x'.repeat(262145) : JSON.stringify(value),{status: isDetail ? detailStatus : status,headers:{'content-type':contentType,'retry-after':'120'}});
        }};
    const execute = vm.runInNewContext(`(async function(workspaceKey){${source}\n})`, context);
    return { result: JSON.parse(await execute(workspace)), requests };
}
test('read-only summary and history requests; strict output allowlist excludes internal identifiers, codes and posts', async()=>{
    const {result,requests}=await run();
    assert.equal(requests.length,2);
    assert.equal(requests[0].url,'/api/v1/zcre-next/metrics');
    assert.equal(requests[0].options.method,'GET');
    assert.equal(requests[0].options.redirect,'error');
    assert.deepEqual(Object.keys(result.metrics).sort(),['accounts','change7d','collectionPaused','totalFollowers','updatedAt'].sort());
    assert.deepEqual(Object.keys(result.metrics.accounts[0]).sort(),['platform','handle','followers','change7d','observedAt','status','derivedAvailable','daily','trendUnavailable'].sort());
    assert.equal(result.metrics.accounts[0].change7d,-2);
    assert.equal(result.metrics.change7d,null);
    assert(!JSON.stringify(result).includes('secret'));
    assert(!JSON.stringify(result).includes('local-test'));
    assert(!JSON.stringify(result).includes('private'));
});
test('wrong account or missing token fails before any server request',async()=>{
    await assert.rejects(run({workspace:'other:personal'}),/authentication/);
    await assert.rejects(run({token:null}),/authentication/);
});
test('account change during request never returns previous metrics',async()=>{await assert.rejects(run({changeSession:true}),/accountChanged/);});
test('429 returns retry-after without parsing data as metrics',async()=>{
    const {result}=await run({status:429}); assert.deepEqual(result,{error:429,retryAfter:'120'});
});
test('HTML, oversized responses and malformed counts fail closed',async()=>{
    await assert.rejects(run({contentType:'text/html'}),/invalidResponse/);
    await assert.rejects(run({large:true}),/invalidResponse/);
    await assert.rejects(run({body:{...payload(),total_followers:-1}}),/invalidResponse/);
    await assert.rejects(run({body:{...payload(),total_followers:'100'}}),/invalidResponse/);
    await assert.rejects(run({body:{...payload(),accounts:Array(33).fill(payload().accounts[0])}}),/invalidResponse/);
});

test('history strips posts and keeps only real daily points', async()=>{
 const {result,requests}=await run();
 assert.equal(requests[1].url,'/api/v1/zcre-next/metrics/accounts/internal?range=30d');
 assert.deepEqual(result.metrics.accounts[0].daily,[{day:'2026-11-08',followers:100}]);
 assert.equal(result.metrics.accounts[0].trendUnavailable,false);
});
test('history rate limit propagates and malformed or mismatched history is not charted',async()=>{
 assert.deepEqual((await run({detailStatus:429})).result,{error:429,retryAfter:'120'});
 for (const detail of [
  {account:{account_id:'wrong',platform:'instagram'},daily:[]},
  {account:payload().accounts[0],daily:[{day:'2026-02-30',followers:1}]},
  {account:payload().accounts[0],daily:[{day:'2026-11-08',followers:1},{day:'2026-11-08',followers:2}]}
 ]) {
  const {result}=await run({detail});
  assert.deepEqual(result.metrics.accounts[0].daily,[]);
  assert.equal(result.metrics.accounts[0].trendUnavailable,true);
 }
});
