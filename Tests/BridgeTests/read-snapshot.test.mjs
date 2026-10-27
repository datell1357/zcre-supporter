// 검증 분류: 모의 fetch를 사용하는 인증·페이지 조회·잔액 캐시 회귀 테스트
import assert from 'node:assert/strict';
import { test } from 'node:test';
import vm from 'node:vm';
import { run, fixture, response, balance, observeSource } from './harness.mjs';

// 회귀 조건: 소수 잔액을 보존하고 허용된 메타데이터만 반환한다.
test('reads exact decimal balances and returns only permitted metadata', async () => {
    const result = await run();
    assert.equal(result.data.balance.available, '90.15');
    assert.equal(result.data.jobs[0].status, 'running_provider');
    assert.equal(result.calls.length, 2);
    assert.ok(!result.json.includes('Private prompt'));
    assert.ok(!result.json.includes('private.invalid'));
    assert.ok(!result.json.includes('fixture-only-token'));
});
// 회귀 조건: 웹 위젯의 동시 생성 사용량·한도 형식을 읽는다.
test('reads current concurrency counts and plan limits from the visible ZCRE widget', async () => {
    const result = await run({ concurrencyLabel: '동시 생성 한도: 전체 5/16, 이미지 2/10, 영상 3/6' });
    assert.deepEqual(result.data.concurrency, { totalActive: 5, totalLimit: 16, imagesActive: 2, imagesLimit: 10, videosActive: 3, videosLimit: 6 });
    assert.equal(result.calls.length, 2);
});
// 회귀 조건: 위젯 누락·변경 시 임의 한도를 만들거나 잔액 조회를 막지 않는다.
test('missing or changed concurrency UI never invents limits or blocks the balance', async () => {
    for (const concurrencyLabel of [undefined, 'loading', '동시 생성 한도: 전체 0/0, 이미지 0/0, 영상 0/0']) {
        const result = await run({ concurrencyLabel });
        assert.equal(result.data.concurrency, null);
        assert.equal(result.data.balance.available, '90.15');
    }
});
// 회귀 조건: 제3자 출처에서는 요청을 시작하지 않는다.
test('refuses to run on any third-party origin', async () => {
    const result = await run({ origin: 'https://zcre.co.kr.attacker.invalid' });
    assert.equal(result.data.error, 'authentication');
    assert.equal(result.calls.length, 0);
});
// 회귀 조건: 로그아웃 상태에서는 API 요청을 보내지 않는다.
test('signed-out sessions do not make API requests', async () => {
    const result = await run({ clerk: { loaded: true } });
    assert.equal(result.data.error, 'authentication');
    assert.equal(result.calls.length, 0);
});
// 회귀 조건: 로그인 HTML 응답을 정상적인 0 잔액으로 받아들이지 않는다.
test('login HTML cannot masquerade as a valid zero balance', async () => {
    const result = await run({ fetch: async () => response('<html>Login</html>', 200, 'text/html') });
    assert.equal(result.data.error, 'invalidResponse');
});
// 회귀 조건: 인증 오류와 요청 제한 오류를 구분한다.
test('401 and 429 have distinct recoverable errors', async () => {
    assert.equal((await run({ fetch: async () => response({}, 401) })).data.error, 'authentication');
    const limited = (await run({ fetch: async () => response({}, 429) })).data;
    assert.equal(limited.error, 'http'); assert.equal(limited.status, 429);
});
// 회귀 조건: 이력 조회 실패를 정상 빈 목록으로 처리하지 않는다.
test('history failure rejects the whole snapshot rather than missing completions', async () => {
    const result = await run({ fetch: async url => url.endsWith('/balance') ? response(balance) : response({}, 503) });
    assert.equal(result.data.error, 'http'); assert.equal(result.data.balance, undefined);
});
// 회귀 조건: 다음 페이지를 읽고 작업 ID 중복을 제거한다.
test('follows pagination and deduplicates job identities', async () => {
    const result = await run({ fetch: async url => url.endsWith('/balance') ? response(balance) : url.includes('cursor=') ? response({ items: [fixture('a'), fixture('b')], next_cursor: null }) : response({ items: [fixture('a')], next_cursor: 'page2' }) });
    assert.deepEqual(result.data.jobs.map(j => j.id), ['a', 'b']);
    assert.equal(result.calls.length, 3);
});
// 회귀 조건: 이력 범위 밖의 알려진 미완료 작업을 개별 조회한다.
test('refreshes known active jobs that have fallen out of the history window', async () => {
    const result = await run({ activeIDs: ['old-job'], fetch: async url => url.endsWith('/balance') ? response(balance) : url.includes('/requests/') ? response({ ...fixture('old-job'), status: 'succeeded' }) : response({ items: [fixture('a')], next_cursor: null }) });
    assert.equal(result.data.jobs.find(j => j.id === 'old-job').status, 'succeeded');
});
// 회귀 조건: 삭제된 작업을 성공으로 알리지 않고 추적을 종료한다.
test('deleted job is retired without falsely declaring success', async () => {
    const previous = { id: 'gone', model: 'seedance-2.5', mediaType: 'video', status: 'running', createdAt: '2026-10-24T12:00:00Z' };
    const result = await run({ activeIDs: ['gone'], previousJobs: [previous], fetch: async url => url.endsWith('/balance') ? response(balance) : url.includes('/requests/') ? response({}, 404) : response({ items: [], next_cursor: null }) });
    assert.equal(result.data.jobs[0].status, 'cancelled');
});
// 회귀 조건: 요청 중 계정 변경이 일어나면 혼합된 데이터를 버린다.
test('detects account change during a request and discards mixed data', async () => {
    const result = await run({ fetch: async (url, clerk) => { clerk.user.id = 'another-fixture-user'; return response(balance); } });
    assert.equal(result.data.error, 'accountChanged');
});
// 회귀 조건: 새 계정 조회에 이전 계정 작업 ID를 사용하지 않는다.
test('new accounts never receive requests containing prior account job IDs', async () => {
    const result = await run({ previousWorkspaceKey: 'different-user:personal', activeIDs: ['private-prior-job'] });
    assert.ok(result.calls.every(call => !call.url.includes('private-prior-job')));
});
// 회귀 조건: 반복 커서가 나오면 무한 페이지 조회를 중단한다.
test('repeating cursor is rejected rather than looping indefinitely', async () => {
    const result = await run({ fetch: async url => url.endsWith('/balance') ? response(balance) : response({ items: [fixture('a')], next_cursor: 'same' }) });
    assert.equal(result.data.error, 'invalidResponse');
    assert.equal(result.calls.length, 3);
});
// 회귀 조건: 지원하지 않는 결제 단위를 크레딧으로 표시하지 않는다.
test('unsupported unit workspaces are not mislabeled as credits', async () => {
    const result = await run({ fetch: async () => response({ ...balance, usage_balance_type: 'unit' }) });
    assert.equal(result.data.error, 'unsupportedWorkspace');
});
// 회귀 조건: 페이지 상한을 넘는 이력은 불완전하다고 표시한다.
test('large histories are explicitly marked incomplete at the page bound', async () => {
    const result = await run({ fetch: async (url, clerk, count) => url.endsWith('/balance') ? response(balance) : response({ items: [fixture(String(count))], next_cursor: String(count) }) });
    assert.equal(result.data.historyTruncated, true);
    assert.equal(result.calls.length, 21);
});
// 회귀 조건: 최초 이력 잘림 표시를 후속 증분 조회에서도 유지한다.
test('an initial truncated scan stays visible on subsequent incremental polls', async () => {
    const result = await run({ previousHistoryTruncated: true, since: Date.now() });
    assert.equal(result.data.historyTruncated, true);
});

// 회귀 조건: SPA 로그인·조직 변경을 식별자 유출 없이 통지한다.
test('session listener refreshes after SPA sign-in and workspace change without exposing identity', () => {
    const messages = []; let listener;
    const clerk = { loaded: true, user: null, session: null, addListener(fn) { listener = fn; } };
    const context = vm.createContext({ location: { origin: 'https://www.zcre.co.kr' }, window: { Clerk: clerk, webkit: { messageHandlers: { zcreSessionChanged: { postMessage: message => messages.push(message) } } } } });
    new vm.Script(observeSource).runInContext(context);
    assert.equal(messages.length, 1);
    clerk.user = { id: 'private-user-id' }; clerk.session = { id: 'private-session-id' }; listener();
    assert.equal(messages.length, 2);
    listener(); // Token refresh without identity change must not interrupt polling.
    assert.equal(messages.length, 2);
    clerk.organization = { id: 'private-org-id' }; listener();
    assert.equal(messages.length, 3);
    clerk.session = null; clerk.user = null; listener();
    assert.equal(messages.length, 4);
    assert.deepEqual(messages, ['ready', 'changed', 'changed', 'changed']);
});

// 회귀 조건: 인증 SDK 준비를 기다리고 OAuth 제공자 출처에는 연결하지 않는다.
test('session listener waits for Clerk to load and never attaches on OAuth origins', () => {
    const messages = []; let tick; let cleared = false;
    const window = { webkit: { messageHandlers: { zcreSessionChanged: { postMessage: message => messages.push(message) } } } };
    const context = vm.createContext({ location: { origin: 'https://zcre.co.kr' }, window, setInterval: fn => { tick = fn; return 42; }, clearInterval: id => { assert.equal(id, 42); cleared = true; } });
    new vm.Script(observeSource).runInContext(context);
    assert.equal(messages.length, 0);
    window.Clerk = { loaded: true, addListener() {} }; tick();
    assert.equal(messages.length, 1); assert.equal(cleared, true);
    new vm.Script(observeSource).runInContext(vm.createContext({ location: { origin: 'https://accounts.example.com' } }));
});

const priorJob = (id = 'a', status = 'running') => ({ id, model: 'seedance-2.5', mediaType: 'video', status, createdAt: fixture(id).created_at });
const cached = (overrides = {}) => ({ previousBalance: { total: '100.25', reserved: '10.10', available: '90.15' }, previousBalanceFetchedAt: Date.now(), previousJobs: [priorJob()], since: Date.now(), ...overrides });
// 회귀 조건: 정상 상태에서 작은 이력 한 페이지만 읽고 잔액을 재사용한다.
test('steady state reads one small history page and reuses exact credits', async () => {
    const result = await run(cached());
    assert.equal(result.calls.length, 1);
    assert.equal(result.calls[0].url, '/api/v1/requests?limit=20');
    assert.equal(result.data.balance.available, '90.15');
    assert.equal(result.data.balanceIsStale, false);
});
// 회귀 조건: 60초 경과 또는 명시적 갱신 시 잔액을 다시 읽는다.
test('credits refresh after sixty seconds or explicit refresh', async () => {
    for (const options of [cached({ previousBalanceFetchedAt: Date.now() - 61000 }), cached({ forceBalance: true })]) {
        const result = await run(options);
        assert.equal(result.calls.length, 2);
        assert.ok(result.calls[1].url.endsWith('/balance'));
    }
});
// 회귀 조건: 새 작업·상태 전이 시 잔액을 갱신하고 짧은 정산 확인 구간을 연다.
test('a new job or status transition refreshes credits and schedules settlement checks', async () => {
    for (const history of [[fixture('new')], [{ ...fixture('a'), status: 'succeeded' }], [{ ...fixture('a'), status: 'failed' }]]) {
        const result = await run(cached({ fetch: async url => url.endsWith('/balance') ? response({ ...balance, available_credit_balance: '70.15' }) : response({ items: history, next_cursor: null }) }));
        assert.equal(result.data.balance.available, '70.15');
        assert.ok(result.data.balanceRefreshUntil > Date.now());
        assert.equal(result.calls.length, 2);
    }
});
// 회귀 조건: 작업 수가 같아도 작업 교체와 크레딧 사용을 감지한다.
test('same active count still catches replacement jobs and credit spending', async () => {
    const result = await run(cached({ fetch: async url => url.endsWith('/balance') ? response(balance) : response({ items: [{ ...fixture('a'), status: 'succeeded' }, fixture('b')], next_cursor: null }) }));
    assert.equal(result.calls.length, 2);
    assert.equal(result.data.jobs.find(j => j.id === 'a').status, 'succeeded');
    assert.equal(result.data.jobs.find(j => j.id === 'b').status, 'running_provider');
});
// 회귀 조건: 잔액 조회 실패 시 완료 상태는 유지하고 잔액만 오래됨으로 표시한다.
test('credit failure preserves fresh completion and marks only cached credits stale', async () => {
    const result = await run(cached({ fetch: async url => url.endsWith('/balance') ? response({}, 503) : response({ items: [{ ...fixture('a'), status: 'succeeded' }], next_cursor: null }) }));
    assert.equal(result.data.jobs[0].status, 'succeeded');
    assert.equal(result.data.balance.available, '90.15');
    assert.equal(result.data.balanceIsStale, true);
    assert.ok(result.data.balanceRetryAt > Date.now());
    const retry = await run(cached({ previousBalanceIsStale: true, balanceRetryAt: result.data.balanceRetryAt }));
    assert.equal(retry.calls.length, 1);
    assert.equal(retry.data.balanceIsStale, true);
});
// 회귀 조건: 작업 전이 후 짧은 구간 동안 정산된 잔액을 재확인한다.
test('credit settlement is rechecked during the short follow-up window', async () => {
    const result = await run(cached({ balanceRefreshUntil: Date.now() + 12000 }));
    assert.equal(result.calls.length, 2);
});
// 회귀 조건: 계정이 바뀌면 잔액 캐시를 넘겨 사용하지 않는다.
test('cached credits never cross an account switch', async () => {
    const result = await run(cached({ previousWorkspaceKey: 'another-user:personal', activeIDs: ['private-prior-id'] }));
    assert.ok(result.calls[0].url.endsWith('/balance'));
    assert.ok(result.calls.every(call => !call.url.includes('private-prior-id')));
});
// 회귀 조건: 잔액 갱신 중 인증 오류는 기존 계정 스냅샷을 무효화한다.
test('authentication failure during credit refresh discards the account snapshot', async () => {
    const result = await run(cached({ forceBalance: true, fetch: async url => url.endsWith('/balance') ? response({}, 401) : response({ items: [fixture('a')], next_cursor: null }) }));
    assert.equal(result.data.error, 'authentication');
    assert.equal(result.data.jobs, undefined);
});
// 회귀 조건: 작업·잔액 요청 제한의 Retry-After 정보를 네이티브로 전달한다.
test('server retry-after is returned for job and credit throttling', async () => {
    const limited = () => { const r = response({}, 429); r.headers.set('retry-after', '90'); return r; };
    const all = await run(cached({ fetch: async () => limited() }));
    assert.equal(all.data.retryAfter, 90);
    const credit = await run(cached({ forceBalance: true, fetch: async url => url.endsWith('/balance') ? limited() : response({ items: [fixture('a')], next_cursor: null }) }));
    assert.equal(credit.data.retryAfter, 90);
    assert.equal(credit.data.balanceIsStale, true);
});
// 회귀 조건: 한 페이지보다 많은 새 작업도 증분 페이지 조회로 보존한다.
test('incremental pagination preserves a burst larger than one page', async () => {
    const recent = { ...fixture('new'), created_at: new Date().toISOString() };
    const result = await run(cached({ fetch: async url => url.endsWith('/balance') ? response(balance) : url.includes('cursor=') ? response({ items: [fixture('a')], next_cursor: null }) : response({ items: [recent], next_cursor: 'next' }) }));
    assert.equal(result.data.jobs.length, 2);
    assert.equal(result.calls.filter(c => c.url.includes('/requests')).length, 2);
});
// 회귀 조건: 종료 이력 제한 때문에 오래된 미완료 작업이 삭제되지 않는다.
test('bounded local terminal history never evicts an older unfinished job', async () => {
    const previousJobs = Array.from({ length: 65 }, (_, i) => priorJob('done-' + i, 'succeeded'));
    previousJobs.push(priorJob('old-active'));
    const result = await run(cached({ previousJobs, activeIDs: ['old-active'], fetch: async url => url.endsWith('/balance') ? response(balance) : url.includes('/requests/') ? response(fixture('old-active')) : response({ items: [], next_cursor: null }) }));
    assert.equal(result.data.jobs.length, 51);
    assert.ok(result.data.jobs.some(j => j.id === 'old-active'));
});

// 회귀 조건: 정상 5초 폴링에서 잔액은 분당 한 번 갱신한다.
test('steady five-second polling refreshes credits once per minute', async () => {
    const base = Date.now(); let state = { balance: { total: '100.25', reserved: '10.10', available: '90.15' }, balanceFetchedAt: base, jobs: [priorJob()] };
    let jobReads = 0, balanceReads = 0;
    for (let tick = 0; tick <= 24; tick++) {
        const result = await run(cached({ now: base + tick * 5000, since: base + Math.max(0, tick - 1) * 5000,
            previousBalance: state.balance, previousBalanceFetchedAt: state.balanceFetchedAt, previousJobs: state.jobs,
            balanceRefreshUntil: state.balanceRefreshUntil ?? 0, balanceRetryAt: state.balanceRetryAt ?? 0 }));
        assert.equal(result.data.balance.available, '90.15');
        jobReads += result.calls.filter(c => c.url.includes('/requests')).length;
        balanceReads += result.calls.filter(c => c.url.endsWith('/balance')).length;
        state = result.data;
    }
    assert.equal(jobReads, 25); assert.equal(balanceReads, 2);
});
// 회귀 조건: 잔액 캐시가 있어도 작업 조회 실패를 성공 빈 목록으로 바꾸지 않는다.
test('cached credit balance cannot turn failed work queries into empty successful snapshots', async () => {
    const result = await run(cached({ fetch: async () => response({}, 503) }));
    assert.equal(result.data.error, 'http');
    assert.equal(result.data.jobs, undefined);
});
