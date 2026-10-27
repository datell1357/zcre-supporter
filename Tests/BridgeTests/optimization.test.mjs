// 검증 분류: 대량 이력·승인되지 않은 응답·계정 전환에서도 정확도를 유지하는 변경 캐시
import assert from 'node:assert/strict';
import test from 'node:test';
import { run, fixture, balance, response } from './harness.mjs';

const base = 1_700_000_000_000;
const rows = Array.from({length:80}, (_, i) => ({...fixture(`burst-${i}`), status:'succeeded', created_at:new Date(base-1000-i*200).toISOString()}));
const creditReads = result => result.calls.filter(call => call.url.endsWith('/balance')).length;

// 실제 네이티브처럼 종료 이력 50개만 다음 브리지에 넘기고 서버의 페이지 응답을 흉내 낸다.
async function tick(prior, now, records = rows, overrides = {}) {
    let terminals = 0;
    const result = await run({
        now, since:prior?.now ?? 0, previousWorkspaceKey:prior ? 'fixture-user:personal' : '',
        previousJobs:(prior?.data.jobs ?? []).filter(job => !['succeeded','failed','cancelled'].includes(job.status) || ++terminals <= 50),
        previousBalance:prior?.data.balance, previousBalanceFetchedAt:prior?.data.balanceFetchedAt,
        balanceRefreshUntil:prior?.data.balanceRefreshUntil, bridgeCache:prior?.bridgeCache,
        fetch:async url => {
            if (url.endsWith('/balance')) return response(balance);
            if (url.includes('/requests/')) return response(records.find(row => row.request_id === url.split('/').pop()));
            const query = new URL(url, 'https://fixture.invalid').searchParams;
            const start = Number(query.get('cursor') ?? 0), limit = Number(query.get('limit'));
            return response({items:records.slice(start,start+limit), next_cursor:start+limit < records.length ? String(start+limit) : null});
        }, ...overrides
    });
    return {...result, now};
}

// 처음 감지한 작업의 정산 확인은 유지하지만 화면 밖의 같은 이력을 매번 새 변경으로 세지 않는다.
test('warm burst cache stops false balance refreshes and uses two supported 50-item pages', async () => {
    let state = await tick(null, base);
    assert.equal(state.data.jobs.length, 80);
    for (const offset of [5000,10000]) { state = await tick(state,base+offset); assert.equal(creditReads(state),1); }
    for (const offset of [15000,20000,25000,30000,35000]) {
        state = await tick(state,base+offset);
        assert.equal(creditReads(state),0);
        assert.equal(state.calls.length,2);
        assert.ok(state.calls.every(call => call.url.includes('limit=50')));
        assert.equal(state.data.jobs.length,50);
        assert.equal(state.bridgeCache.states.size,80);
    }
});

// 네이티브가 취소하거나 거부한 후보 캐시는 재사용하지 않고 실제 작업·잔액을 다시 확인한다.
test('unacknowledged cache cannot suppress a credit refresh', async () => {
    const state = await tick(null,base);
    const rejected = await tick(state,base+20000,rows,{acceptedSnapshotRevision:'not-accepted'});
    assert.equal(creditReads(rejected),1);
});

// 세션 또는 계정이 바뀌면 변경 감지 기록으로 이전 계정의 상태를 추정하지 않는다.
test('change cache is scoped to both user and session', async () => {
    const state = await tick(null,base);
    const newSession = {loaded:true,user:{id:'fixture-user'},session:{id:'new-session',getToken:async ()=>'fixture-only-token'}};
    const renewed = await tick(state,base+20000,rows,{clerk:newSession});
    assert.equal(creditReads(renewed),1);
    assert.equal(renewed.bridgeCache.sessionID,'new-session');
    const other = await tick(state,base+20000,[],{clerk:{...newSession,user:{id:'other-user'}}});
    assert.equal(other.data.jobs.length,0);
    assert.equal(other.data.workspaceKey,'other-user:personal');
    assert.equal(creditReads(other),1);
});

// 같은 개수의 작업이 서로 교체되거나 화면 밖 이력의 상태가 변경되면 빠른 잔액 확인을 유지한다.
test('cached history still detects new IDs and terminal state changes', async () => {
    const first = await tick(null,base);
    const changedRows = rows.map((row,i) => i === 60 ? {...row,status:'failed'} : row);
    const changed = await tick(first,base+20000,changedRows);
    assert.equal(creditReads(changed),1);
    assert.equal(changed.bridgeCache.states.get('burst-60').status,'failed');
    const newRows = [{...fixture('new-job'),created_at:new Date(base+21000).toISOString()},...changedRows];
    const active = await tick(changed,base+25000,newRows);
    assert.equal(creditReads(active),1);
    assert.ok(active.data.jobs.some(job => job.id === 'new-job' && job.status === 'running_provider'));
});

// 목록 조회 실패는 새 캐시를 확정하지 않으므로 다음 성공 조회가 변경을 다시 감지할 수 있다.
test('failed read leaves the previous cache uncommitted', async () => {
    const first = await tick(null,base);
    const failed = await tick(first,base+20000,rows,{fetch:async () => response({},503)});
    assert.equal(failed.data.error,'http');
    assert.equal(failed.bridgeCache.revision,first.bridgeCache.revision);
});

// 10분 보관 기한 및 항목 상한을 지키며 최근 작업의 기록은 보존한다.
test('change cache expires old records and stays bounded', async () => {
    const first = await tick(null,base);
    first.bridgeCache.states.set('expired',{status:'succeeded',createdAt:base-700000,seenAt:base-700000});
    for(let i=0;i<10001;i++) first.bridgeCache.states.set(`old-${i}`,{status:'succeeded',createdAt:base-120000,seenAt:base-1});
    const next = await tick(first,base+20000);
    assert.equal(next.bridgeCache.states.size,10000);
    assert.equal(next.bridgeCache.states.has('expired'),false);
    assert.equal(next.bridgeCache.states.has('burst-79'),true);
});

// 적은 작업에는 작은 페이지를 유지하고, 목록 밖 미완료 작업은 계속 개별 조회한다.
test('small history keeps 20-item reads and never skips known unfinished work', async () => {
    const old = {...fixture('old-active'),created_at:new Date(base-600000).toISOString()};
    const first = await tick(null,base,[...rows.slice(0,3),old]);
    const next = await tick(first,base+20000,rows.slice(0,3),{
        activeIDs:['old-active'],
        fetch:async url => url.endsWith('/balance') ? response(balance) : url.endsWith('/old-active') ? response({...old,status:'succeeded'}) : response({items:rows.slice(0,3),next_cursor:null})
    });
    assert.ok(next.calls.some(call => call.url.includes('limit=20')));
    assert.ok(next.calls.some(call => call.url.endsWith('/old-active')));
    assert.ok(next.data.jobs.some(job => job.id === 'old-active' && job.status === 'succeeded'));
    assert.equal(creditReads(next),1);
});
