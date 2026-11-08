// 기능 분류: 프로필 메트릭 요약 GET. HTML·게시물·인증 정보는 네이티브로 전달하지 않는다.
if (!["https://www.zcre.co.kr", "https://zcre.co.kr"].includes(location.origin)) throw new Error("authentication");
const clerk = window.Clerk;
const user = clerk?.user?.id, session = clerk?.session?.id, org = clerk?.organization?.id ?? null;
const same = () => window.Clerk?.user?.id === user && window.Clerk?.session?.id === session && (window.Clerk?.organization?.id ?? null) === org;
if (!user || !session || `${user}:${org ?? 'personal'}` !== workspaceKey) throw new Error("authentication");
const controller = new AbortController();
window.__zcreSupporterMetricsAbort?.abort();
window.__zcreSupporterMetricsAbort = controller;
const timer = setTimeout(() => controller.abort(), 12000);
try {
    const token = await clerk.session.getToken();
    if (!same() || !token) throw new Error("authentication");
    // JSON만 읽으며 채널별 추이는 순차 조회해 동시 요청을 늘리지 않는다.
    const read = async path => {
        const response = await fetch(path, {
            method: "GET", credentials: "same-origin", redirect: "error", cache: "no-store",
            headers: { Authorization: `Bearer ${token}`, Accept: "application/json" }, signal: controller.signal
        });
        if (!same()) throw new Error("accountChanged");
        if (!response.ok) throw { status: response.status, retryAfter: response.headers.get("retry-after") };
        if (!response.headers.get("content-type")?.toLowerCase().includes("application/json")) throw new Error("invalidResponse");
        if (Number(response.headers.get("content-length")) > 262144) throw new Error("invalidResponse");
        const reader = response.body.getReader();
        const chunks = []; let size = 0;
        while (true) {
            const part = await reader.read();
            if (part.done) break;
            size += part.value.byteLength;
            if (size > 262144) { await reader.cancel(); throw new Error("invalidResponse"); }
            chunks.push(part.value);
        }
        const bytes = new Uint8Array(size); let offset = 0;
        for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
        const result = JSON.parse(new TextDecoder().decode(bytes));
        if (!same()) throw new Error("accountChanged");
        return result;
    };
    const payload = await read("/api/v1/zcre-next/metrics");
    if (!same()) throw new Error("accountChanged");
    if (!Array.isArray(payload.accounts) || payload.accounts.length > 32) throw new Error("invalidResponse");
    const number = (n, signed = false) => {
        if (n === null || n === undefined) return null;
        if (!Number.isSafeInteger(n) || Math.abs(n) > 1e12 || (!signed && n < 0)) throw new Error("invalidResponse");
        return n;
    };
    const text = (s, max) => {
        if (typeof s !== "string" || !s.trim() || s.length > max) throw new Error("invalidResponse");
        return s;
    };
    const date = s => {
        if (s === null || s === undefined) return null;
        if (typeof s !== "string" || s.length > 40 || !Number.isFinite(Date.parse(s))) throw new Error("invalidResponse");
        return new Date(s).toISOString();
    };
    // 식별자는 URL 구성·응답 일치 확인에만 사용하고 네이티브에는 전달하지 않는다.
    const accounts = [];
    for (const a of payload.accounts) {
        const account = { platform: text(a.platform, 32), handle: text(a.handle, 128),
            followers: number(a.followers), change7d: number(a.followers_change_7d, true),
            observedAt: date(a.last_observed_at), status: text(a.collection_status, 40),
            derivedAvailable: a.derived_metrics_available === true, daily: [], trendUnavailable: false };
        try {
            if (typeof a.account_id !== "string" || !/^[A-Za-z0-9_-]{1,80}$/.test(a.account_id)) throw new Error("invalidResponse");
            const detail = await read(`/api/v1/zcre-next/metrics/accounts/${encodeURIComponent(a.account_id)}?range=30d`);
            if (detail.account?.account_id !== a.account_id || detail.account?.platform !== a.platform || !Array.isArray(detail.daily) || detail.daily.length > 32) throw new Error("invalidResponse");
            const seen = new Set();
            account.daily = detail.daily.map(p => {
                if (typeof p.day !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(p.day) || !Number.isFinite(Date.parse(p.day)) || new Date(p.day).toISOString().slice(0,10) !== p.day || seen.has(p.day)) throw new Error("invalidResponse");
                seen.add(p.day);
                return { day: p.day, followers: number(p.followers) };
            }).sort((a,b) => a.day.localeCompare(b.day));
        } catch (error) {
            if (!same() || controller.signal.aborted) throw new Error("accountChangedOrCancelled");
            if ([401,403,429].includes(error.status)) throw error;
            account.daily = []; account.trendUnavailable = true;
        }
        accounts.push(account);
    }
    return JSON.stringify({ metrics: {
        totalFollowers: number(payload.total_followers), change7d: number(payload.total_followers_change_7d, true),
        updatedAt: date(payload.updated_at), collectionPaused: Boolean(payload.collection_paused_reason), accounts
    }});
} catch (error) {
    if (Number.isInteger(error.status)) return JSON.stringify({error: error.status, retryAfter: error.retryAfter});
    throw error;
} finally { clearTimeout(timer); }
