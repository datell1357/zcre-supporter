// 자격 증명·식별자를 내보내지 않고 로그인·로그아웃·워크스페이스 변경을 관찰한다.
// 기능 분류: 로그인 변경 관찰. 인증 정보나 식별자 대신 준비·변경 이벤트만 네이티브에 보낸다.
(() => {
    if (!["https://www.zcre.co.kr", "https://zcre.co.kr"].includes(location.origin)) return;
    let lastIdentity;
    // 현재 계정 조합이 달라진 경우에만 이벤트를 보내 불필요한 재조회 시작을 줄인다.
    const notify = () => {
        const clerk = window.Clerk;
        const identity = JSON.stringify([clerk?.user?.id ?? null, clerk?.session?.id ?? null, clerk?.organization?.id ?? null]);
        if (identity !== lastIdentity) {
            const event = lastIdentity === undefined ? "ready" : "changed";
            lastIdentity = identity;
            window.webkit?.messageHandlers?.zcreSessionChanged?.postMessage(event);
        }
    };
    let attempts = 0;
    // Clerk가 준비되면 리스너를 한 번 등록하고 현재 상태를 전달한다.
    const attach = () => {
        if (!window.Clerk?.loaded || typeof window.Clerk.addListener !== "function") return false;
        window.Clerk.addListener(notify);
        notify();
        return true;
    };
    // 최대 30초까지만 인증 SDK 준비를 기다린다. 이 타이머 자체는 HTTP 요청을 만들지 않는다.
    if (!attach()) {
        const timer = setInterval(() => {
            if (attach() || ++attempts >= 120) clearInterval(timer);
        }, 250);
    }
})();
