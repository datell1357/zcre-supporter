// 앱의 인증된 WebKit 페이지에서만 실행하며 자격 증명은 브리지로 넘기지 않는다.
// 분류: 인증 경계. 앱의 ZCRE 페이지에서만 실행하며 토큰은 이 JavaScript 실행 범위에만 둔다.
const allowedOrigins = new Set(["https://www.zcre.co.kr", "https://zcre.co.kr"]);
if (!allowedOrigins.has(location.origin)) return JSON.stringify({ error: "authentication" });
const clerk = window.Clerk;
if (!clerk?.loaded || !clerk.session || !clerk.user) return JSON.stringify({ error: "authentication" });
const userID = clerk.user.id, sessionID = clerk.session.id, organizationID = clerk.organization?.id ?? null;
const workspaceKey = `${userID}:${organizationID ?? "personal"}`;
const isSameWorkspace = previousWorkspaceKey === workspaceKey;
// 비동기 호출 사이에 사용자·세션·조직이 바뀌었는지 확인해 계정 데이터가 섞이는 것을 막는다.
const sameAccount = () => window.Clerk?.user?.id === userID && window.Clerk?.session?.id === sessionID && (window.Clerk?.organization?.id ?? null) === organizationID;
// 분류: 취소와 시간 제한. 이전 실행을 취소하고 전체 조회에 20초 제한을 둔다.
const controller = new AbortController();
window.__zcreSupporterReadAbort?.abort();
window.__zcreSupporterReadAbort = controller;
const timeout = setTimeout(() => controller.abort(), 20000);
const startedAt = Date.now();
// 크레딧 소수 문자열을 검증하고 문자열로 유지해 브리지 전달 시 부동소수점 손실을 피한다.
const numeric = value => {
    if ((typeof value !== "string" && typeof value !== "number") || !/^-?\d+(?:\.\d+)?$/.test(String(value))) throw { kind: "invalidResponse" };
    return String(value);
};
// 서버 상태 별칭을 공통 상태로 묶어 이름만 다른 동일 상태를 변경으로 오인하지 않는다.
const statusGroup = value => {
    const status = value.toLowerCase();
    if (["pending", "queued", "accepted", "submitted", "waiting", "received", "validated", "queued_internal"].includes(status)) return "queued";
    if (["running", "processing", "in_progress", "generating", "submitting_provider", "submitted_provider", "running_provider", "asset_ingesting"].includes(status)) return "running";
    if (["succeeded", "completed", "complete", "success"].includes(status)) return "succeeded";
    if (["failed", "error", "timeout", "timed_out"].includes(status)) return "failed";
    if (["cancelled", "canceled"].includes(status)) return "cancelled";
    return "unknown";
};
try {
    // 현재 로그인 세션의 토큰을 얻는다. 실제 인증 서버 호출 여부는 Clerk의 캐시 정책에 달려 있다.
    const token = await Promise.race([
        clerk.session.getToken(),
        new Promise((_, reject) => controller.signal.addEventListener("abort", () => reject({ kind: "network" }), { once: true }))
    ]);
    if (!sameAccount()) return JSON.stringify({ error: "accountChanged" });
    if (!token) return JSON.stringify({ error: "authentication" });
    // 허용된 조회 경로에만 GET을 보내며 리디렉션을 따라 인증 정보를 다른 경로에 전달하지 않는다.
    const read = async path => {
        if (!/^\/api\/v1\/(billing\/balance|requests(?:\?[^#]*|\/[^/?#]+)?)$/.test(path)) throw { kind: "invalidResponse" };
        const response = await fetch(path, {
            method: "GET", credentials: "same-origin", cache: "no-store", redirect: "error",
            headers: { "Authorization": `Bearer ${token}`, "Accept": "application/json" }, signal: controller.signal
        });
        if (!sameAccount()) throw { kind: "accountChanged" };
        if (response.status === 401 || response.status === 403) throw { kind: "authentication" };
        if (!response.ok) {
            const header = response.headers.get("retry-after");
            const seconds = header ? (/^\d+(?:\.\d+)?$/.test(header) ? Number(header) : (Date.parse(header) - Date.now()) / 1000) : 0;
            throw { kind: "http", status: response.status, retryAfter: Number.isFinite(seconds) ? Math.max(0, seconds) : 0 };
        }
        if (!response.headers.get("content-type")?.includes("application/json")) throw { kind: "invalidResponse" };
        return response.json();
    };
    // 분류: 계정별 잔액 캐시. 다른 계정의 값과 재시도 시각은 재사용하지 않는다.
    const cached = isSameWorkspace && previousBalance && previousBalanceFetchedAt > 0;
    let balance = cached ? previousBalance : null;
    let balanceFetchedAt = cached ? previousBalanceFetchedAt : 0;
    let balanceIsStale = cached && previousBalanceIsStale;
    let fastUntil = isSameWorkspace ? balanceRefreshUntil : 0;
    let retryAt = isSameWorkspace ? balanceRetryAt : 0;
    let retryAfter = 0;
    // 잔액 단위와 필수 필드를 검증한 뒤 성공한 시각에만 잔액의 신선도를 갱신한다.
    const readBalance = async () => {
        const value = await read("/api/v1/billing/balance");
        if (value.usage_balance_type !== "credit" || value.available_credit_balance == null) throw { kind: "unsupportedWorkspace" };
        balance = { total: numeric(value.credit_balance), reserved: numeric(value.reserved_credit_balance), available: numeric(value.available_credit_balance) };
        balanceFetchedAt = Date.now(); balanceIsStale = false; retryAt = 0;
    };
    // 새 계정의 잔액을 직접 확인하고 다른 계정의 잔액 캐시는 사용하지 않는다.
    if (!cached) await readBalance();
    const jobs = new Map();
    const previous = new Map((isSameWorkspace ? previousJobs : []).map(job => [job.id, job]));
    // 화면 이력 50개와 변경 감지 기록을 분리한다. 네이티브가 수락한 직전 응답만 캐시로 인정한다.
    // 실패·취소·계정 전환·페이지 재로드 후에는 기존 스냅샷으로 안전하게 다시 시작한다.
    const oldCache = window.__zcreSupporterChangeCache;
    const acceptedCache = isSameWorkspace && oldCache?.workspaceKey === workspaceKey &&
        oldCache?.sessionID === sessionID && oldCache?.revision === acceptedSnapshotRevision;
    const observed = new Map(acceptedCache ? [...oldCache.states].filter(([, value]) =>
        startedAt >= value.seenAt && startedAt - value.seenAt <= 600000) : []);
    // 서버 응답 중 표시·감시에 필요한 필드만 네이티브에 넘긴다. 원래 HTTP 응답 크기를 줄이는 처리는 아니다.
    const normalize = item => {
        if (!item || typeof item.request_id !== "string" || typeof item.model_name !== "string" || typeof item.status !== "string" || typeof item.created_at !== "string" || !Number.isFinite(Date.parse(item.created_at))) throw { kind: "invalidResponse" };
        return { id: item.request_id, model: item.model_name, mediaType: item.media_type ?? "image", status: item.status, createdAt: item.created_at };
    };
    let cursor = null;
    const cursors = new Set();
    let truncated = isSameWorkspace && previousHistoryTruncated;
    // 평소에는 20개만 받는다. 겹침 구간에 이미 많은 기록이 있으면 지원되는 50개 단위로 페이지 수를 줄인다.
    const recentIDs = new Set([...previous.values()].filter(job => Date.parse(job.createdAt) >= since - 60000).map(job => job.id));
    for (const [id, value] of observed) if (value.createdAt >= since - 60000) recentIDs.add(id);
    const pageSize = !cached || recentIDs.size > 20 ? 50 : 20;
    // 분류: 이력 조회. 한 조회 안에서는 페이지 크기를 고정하고 최대 20페이지·반복 커서 차단을 유지한다.
    for (let page = 0; page < 20; page++) {
        const query = new URLSearchParams({ limit: String(pageSize) });
        if (cursor) query.set("cursor", cursor);
        const history = await read(`/api/v1/requests?${query}`);
        if (!Array.isArray(history.items)) throw { kind: "invalidResponse" };
        for (const item of history.items) { const job = normalize(item); jobs.set(job.id, job); }
        cursor = history.next_cursor;
        if (!cursor) break;
        if (cursors.has(cursor)) throw { kind: "invalidResponse" };
        cursors.add(cursor);
        // 최근 조회 구간을 겹쳐 성공 조회 이후 늦게 나타나는 작업도 확인한다.
        if (isSameWorkspace && since && history.items.length && history.items.every(item => Date.parse(item.created_at) < since - 60000)) break;
        if (page === 19) truncated = true;
    }
    // 목록 밖으로 밀려난 미완료 작업은 ID별 GET으로 추적한다. 작업 수에 비례해 추가 요청이 발생한다.
    for (const id of isSameWorkspace ? activeIDs : []) {
        if (jobs.has(id)) continue;
        try { const job = normalize(await read(`/api/v1/requests/${encodeURIComponent(id)}`)); jobs.set(job.id, job); }
        catch (error) {
            if (error.status === 404) {
                const prior = previous.get(id);
                if (prior) jobs.set(id, { ...prior, status: "cancelled" });
            } else throw error;
        }
    }
    // 작업 수만 비교하지 않고 ID와 상태를 비교해 동시 시작·완료를 구분한다.
    // 네이티브의 직전 상태를 우선하고 화면에서 밀려난 종료 이력은 별도 기록과 비교한다.
    const changed = [...jobs.values()].some(job => {
        const known = previous.get(job.id) ?? observed.get(job.id);
        return !known || statusGroup(known.status) !== statusGroup(job.status);
    });
    if (changed) fastUntil = Date.now() + 15000;
    // 잔액은 평소 60초마다 읽고 변경 후 15초 동안 추가 확인한다. 명시적 갱신도 이 경로를 사용한다.
    if (cached && startedAt >= retryAt && (forceBalance || changed || balanceIsStale || startedAt < fastUntil || (startedAt < balanceFetchedAt || startedAt - balanceFetchedAt >= 60000))) {
        try { await readBalance(); }
        catch (error) {
            if (["authentication", "accountChanged", "unsupportedWorkspace"].includes(error.kind)) throw error;
            // 잔액 조회 실패 때문에 이미 확인한 작업 완료를 숨기지 않는다.
            balanceIsStale = true;
            retryAfter = error.status === 429 ? Math.max(30, error.retryAfter || 0) : (error.retryAfter || 0);
            retryAt = Date.now() + Math.max(15000, retryAfter * 1000);
        }
    }
    if (!sameAccount()) return JSON.stringify({ error: "accountChanged" });
    // 메모리 캐시는 성공 응답 후보에만 갱신한다. 다음 호출의 수락 번호가 다르면 재사용하지 않는다.
    for (const job of jobs.values()) observed.set(job.id, { status: statusGroup(job.status), createdAt: Date.parse(job.createdAt), seenAt: startedAt });
    const states = observed.size > 10000 ? new Map([...observed].sort((a, b) => b[1].seenAt - a[1].seenAt).slice(0, 10000)) : observed;
    window.__zcreSupporterChangeCache = { workspaceKey, sessionID, revision: snapshotRevision, states };
    // 최근 종료 이력은 로컬에서 재사용하고 미완료 작업은 보관 제한으로 제거하지 않는다.
    for (const job of previous.values()) if (!jobs.has(job.id)) jobs.set(job.id, job);
    // 미완료 작업은 유지하고 종료 이력만 50개로 제한한다. 이 제한은 서버 이력을 삭제하지 않는다.
    let terminalCount = 0;
    const ordered = [...jobs.values()].sort((a, b) => Date.parse(b.createdAt) - Date.parse(a.createdAt));
    const retained = cached ? ordered.filter(job => ["queued", "running", "unknown"].includes(statusGroup(job.status)) || ++terminalCount <= 50) : ordered;
    // 분류: 웹 요금제 한도. DOM의 사용 개수는 네이티브에서 실제 API 작업 수로 다시 계산한다.
    const label = typeof document === "undefined" ? null : document.querySelector('[aria-label^="동시 생성 한도:"]')?.getAttribute("aria-label");
    const match = label?.match(/^동시 생성 한도:\s*전체 (\d+)\/(\d+),\s*이미지 (\d+)\/(\d+),\s*영상 (\d+)\/(\d+)$/);
    const counts = match?.slice(1).map(Number);
    // 네이티브는 이 요금제 한도를 사용하되 사용량은 동일한 API 작업 목록으로 계산한다.
    const concurrency = counts?.every(Number.isSafeInteger) && counts[1] > 0 && counts[3] > 0 && counts[5] > 0
        ? { totalActive: counts[0], totalLimit: counts[1], imagesActive: counts[2], imagesLimit: counts[3], videosActive: counts[4], videosLimit: counts[5] } : null;
    return JSON.stringify({ workspaceKey, workspaceName: organizationID ? (clerk.organization.name ?? "워크스페이스") : "개인 워크스페이스",
        balance, balanceFetchedAt, balanceIsStale, balanceRefreshUntil: fastUntil, balanceRetryAt: retryAt, retryAfter,
        jobs: retained, historyTruncated: truncated, concurrency });
// 오류 종류와 재시도 정보만 반환하며 토큰·응답 원문은 오류에 포함하지 않는다.
} catch (error) {
    return JSON.stringify({ error: error.kind ?? "network", status: error.status, retryAfter: error.retryAfter || 0 });
// 정상·오류·취소에 관계없이 타임아웃과 현재 실행의 취소 핸들을 정리한다.
} finally {
    clearTimeout(timeout);
    if (window.__zcreSupporterReadAbort === controller) delete window.__zcreSupporterReadAbort;
}
