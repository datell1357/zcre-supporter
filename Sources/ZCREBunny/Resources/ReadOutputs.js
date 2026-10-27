// 기능 분류: 사용자가 선택한 완료 작업의 결과만 조회. 토큰은 WebKit 내부에 유지한다.
if (!["https://www.zcre.co.kr", "https://zcre.co.kr"].includes(location.origin)) throw new Error("authentication");
const clerk = window.Clerk;
const user = clerk?.user?.id, session = clerk?.session?.id, org = clerk?.organization?.id ?? null;
const same = () => window.Clerk?.user?.id === user && window.Clerk?.session?.id === session && (window.Clerk?.organization?.id ?? null) === org;
if (!user || !session || `${user}:${org ?? 'personal'}` !== workspaceKey || !/^[a-zA-Z0-9_-]{1,200}$/.test(requestID)) throw new Error("authentication");
const controller = new AbortController();
window.__zcreSupporterOutputAbort?.abort();
window.__zcreSupporterOutputAbort = controller;
const timer = setTimeout(() => controller.abort(), 15000);
try {
    const token = await clerk.session.getToken();
    if (!same() || !token) throw new Error("authentication");
    const response = await fetch(`/api/v1/requests/${encodeURIComponent(requestID)}/outputs`, {
        method: "GET", credentials: "same-origin", redirect: "error", cache: "no-store",
        headers: { Authorization: `Bearer ${token}`, Accept: "application/json" }, signal: controller.signal
    });
    if (!same()) throw new Error("accountChanged");
    if (!response.ok) return JSON.stringify({ error: response.status, retryAfter: response.headers.get("retry-after") });
    const payload = await response.json();
    if (!same() || !Array.isArray(payload.outputs)) throw new Error("invalidResponse");
    // 프롬프트·입력 파일·인증 정보는 반환하지 않고 결과 링크만 메모리로 전달한다.
    return JSON.stringify({ outputs: payload.outputs.slice(0, 64).map(o => ({
        id: o.output_id, mediaType: o.media_type, contentType: o.content_type,
        url: o.delivery_url ?? o.presigned_url, originalURL: o.original_delivery_url,
        expires: o.expires_in_seconds
    })) });
} finally { clearTimeout(timer); }
