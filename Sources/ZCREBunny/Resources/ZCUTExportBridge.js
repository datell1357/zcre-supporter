// 기능 분류: ZCUT 편집기 내보내기 · 재연결 가능한 폴더와 macOS 다운로드 연결
(() => {
  if (location.protocol !== "https:" || !["zcut.ai", "www.zcut.ai"].includes(location.hostname)) return;
  if (typeof window.showDirectoryPicker === "function") return;
  if (typeof navigator.storage?.getDirectory !== "function") return;

  const prefix = "zcre-supporter-export-";
  const directoryName = "zcre-supporter-export";
  let activeWatcher = null;

  // 이전 방식의 임시 폴더만 정리한다. 현재 결과 폴더는 재연결을 위해 유지한다.
  async function removeOldExports(root) {
    const cutoff = Date.now() - 24 * 60 * 60 * 1000;
    for await (const [name, handle] of root.entries()) {
      if (handle.kind !== "directory" || !name.startsWith(prefix) || name === directoryName) continue;
      const created = Number(name.slice(prefix.length).split("-")[0]);
      if (Number.isFinite(created) && created > 0 && created < cutoff) {
        try { await root.removeEntry(name, { recursive: true }); } catch (_) {}
      }
    }
  }

  // OPFS는 쓰기가 닫힌 뒤 완성 파일을 노출한다. 크기와 수정 시각이 두 번 같을 때 내려받는다.
  function watchForMovie(directory, existingFiles) {
    const stability = new Map();
    let checking = false;
    const timer = setInterval(async () => {
      if (checking) return;
      checking = true;
      try {
        for await (const [name, handle] of directory.entries()) {
          if (handle.kind !== "file" || !/\.mp4$/i.test(name)) continue;
          const file = await handle.getFile();
          if (file.size === 0) continue;
          const fingerprint = `${name}:${file.size}:${file.lastModified}`;
          if (existingFiles.has(fingerprint)) continue;
          const previous = stability.get(name);
          const stable = previous?.fingerprint === fingerprint ? previous.count + 1 : 0;
          stability.set(name, { fingerprint, count: stable });
          if (stable < 2) continue;
          clearInterval(timer);
          activeWatcher = null;
          const url = URL.createObjectURL(file);
          const link = document.createElement("a");
          link.href = url;
          link.download = name;
          link.hidden = true;
          document.body.appendChild(link);
          link.click();
          link.remove();
          setTimeout(() => URL.revokeObjectURL(url), 5 * 60 * 1000);
          return;
        }
      } catch (_) {
        // 파일 쓰기가 끝나지 않았으면 다음 주기에 다시 읽는다.
      } finally {
        checking = false;
      }
    }, 1000);
    activeWatcher = timer;
  }

  window.showDirectoryPicker = async function showDirectoryPicker(options = {}) {
    if (options.id !== "zcut-export" || (options.mode && options.mode !== "readwrite")) {
      const error = new Error("ZCUT 영상 내보내기만 앱 안에서 지원합니다.");
      error.name = "NotSupportedError";
      throw error;
    }
    const root = await navigator.storage.getDirectory();
    await removeOldExports(root);
    const directory = await root.getDirectoryHandle(directoryName, { create: true });
    const probe = await directory.getFileHandle(".zcre-export-probe", { create: true });
    if (typeof probe.createWritable !== "function") {
      throw new Error("이 macOS 버전의 WebKit은 ZCUT 영상 파일 쓰기를 지원하지 않습니다.");
    }
    await directory.removeEntry(".zcre-export-probe");
    const existingFiles = new Set();
    for await (const [name, handle] of directory.entries()) {
      if (handle.kind !== "file" || !/\.mp4$/i.test(name)) continue;
      const file = await handle.getFile();
      existingFiles.add(`${name}:${file.size}:${file.lastModified}`);
    }
    if (activeWatcher !== null) clearInterval(activeWatcher);
    watchForMovie(directory, existingFiles);
    // ZCUT은 선택 직후 readwrite 권한을 확인한다. OPFS는 해당 출처에 이미 부여된 저장소다.
    // 실제 핸들을 반환해야 렌더러의 worker로 구조화 복사가 가능하다.
    try {
      if (typeof directory.queryPermission !== "function") {
        Object.defineProperty(directory, "queryPermission", { value: async () => "granted" });
        Object.defineProperty(directory, "requestPermission", { value: async () => "granted" });
      }
      return directory;
    } catch (_) {}
    try {
      const prototype = Object.getPrototypeOf(directory);
      if (typeof prototype.queryPermission !== "function") {
        Object.defineProperty(prototype, "queryPermission", { value: async () => "granted" });
        Object.defineProperty(prototype, "requestPermission", { value: async () => "granted" });
      }
      return directory;
    } catch (_) {}
    // 핸들과 프로토타입이 모두 잠겨 있는 WebKit 빌드에서는 페이지 내 호출만 지원한다.
    return new Proxy(directory, {
      get(target, property) {
        if (property === "queryPermission" || property === "requestPermission") return async () => "granted";
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });
  };

})();
