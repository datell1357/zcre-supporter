// 검증 분류: 모의 fetch를 사용하는 브리지 인증·페이지 조회·잔액 캐시 테스트. 실제 서버를 호출하지 않는다.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';

export const source = await readFile(new URL('../../Sources/ZCREBunny/Resources/ReadSnapshot.js', import.meta.url), 'utf8');
export const observeSource = await readFile(new URL('../../Sources/ZCREBunny/Resources/ObserveSession.js', import.meta.url), 'utf8');
// 실제 개인정보 대신 고정 작업 예시를 사용하고 브리지가 비공개 필드를 제거하는지 확인한다.
export const fixture = id => ({ request_id: id, model_name: 'seedance-2.5', media_type: 'video', status: 'running_provider', created_at: '2026-10-24T12:00:00Z', prompt: 'Private prompt that must not cross the bridge', output_url: 'https://private.invalid/signed' });
export const balance = { usage_balance_type: 'credit', credit_balance: '100.25', reserved_credit_balance: '10.10', available_credit_balance: '90.15' };
// 네트워크 요청 없이 HTTP 상태·헤더·JSON 응답을 흉내 낸다.
export const response = (data, status = 200, type = 'application/json') => ({ ok: status >= 200 && status < 300, status, headers: new Map([['content-type', type]]), json: async () => data });

let sequence = 0;

// 격리된 JavaScript 문맥에서 실제 브리지 소스를 실행하고 모든 fetch를 로컬 대역으로 기록한다.
export async function run(options = {}) {
    const calls = [];
    const revision = options.snapshotRevision ?? `test-revision-${++sequence}`;
    const clerk = options.clerk ?? { loaded: true, user: { id: 'fixture-user' }, session: { id: 'fixture-session', getToken: async () => 'fixture-only-token' } };
    const context = vm.createContext({
        location: { origin: options.origin ?? 'https://www.zcre.co.kr' }, window: { Clerk: clerk, __zcreSupporterChangeCache: options.bridgeCache },
        URLSearchParams, AbortController, setTimeout, clearTimeout,
        Date: options.now === undefined ? Date : class extends Date { static now() { return options.now; } },
        document: { querySelector: () => options.concurrencyLabel ? { getAttribute: () => options.concurrencyLabel } : null },
        activeIDs: options.activeIDs ?? [], previousJobs: options.previousJobs ?? [], since: options.since ?? 0,
        previousWorkspaceKey: options.previousWorkspaceKey ?? 'fixture-user:personal',
        previousHistoryTruncated: options.previousHistoryTruncated ?? false,
        previousBalance: options.previousBalance ?? null,
        previousBalanceFetchedAt: options.previousBalanceFetchedAt ?? 0,
        previousBalanceIsStale: options.previousBalanceIsStale ?? false,
        balanceRefreshUntil: options.balanceRefreshUntil ?? 0, balanceRetryAt: options.balanceRetryAt ?? 0,
        forceBalance: options.forceBalance ?? false,
        snapshotRevision: revision, acceptedSnapshotRevision: options.acceptedSnapshotRevision ?? options.bridgeCache?.revision ?? "",
        fetch: async (url, init) => {
            calls.push({ url, init });
            assert.equal(init.method, 'GET');
            assert.ok(url.startsWith('/api/v1/'));
            assert.equal(init.redirect, 'error');
            return options.fetch ? options.fetch(url, clerk, calls.length) : url.endsWith('/balance') ? response(balance) : response({ items: [fixture('a')], next_cursor: null });
        }
    });
    const json = await new vm.Script(`(async () => { ${options.source ?? source} })()`).runInContext(context);
    return { data: JSON.parse(json), json, calls, bridgeCache: context.window.__zcreSupporterChangeCache };
}
