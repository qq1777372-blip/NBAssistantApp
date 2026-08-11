(() => {
  async function clearAppCache() {
    if (!confirm("清除旧版界面缓存并重新加载？登录状态和业务数据会保留。")) return;
    if ("serviceWorker" in navigator) {
      const registrations = await navigator.serviceWorker.getRegistrations();
      await Promise.all(registrations.filter((item) => item.scope.includes("/app/")).map((item) => item.unregister()));
    }
    if ("caches" in window) {
      const names = await caches.keys();
      await Promise.all(names.map((name) => caches.delete(name)));
    }
    location.replace(`/app/?cache-cleared=${Date.now()}`);
  }

  function install() {
    if (!location.pathname.includes("/tabs/app-settings")) return;
    const list = document.querySelector("main.page-pad .compact-list");
    if (!list || list.querySelector("[data-clear-app-cache]")) return;
    const button = document.createElement("button");
    button.type = "button";
    button.className = "compact-row setting";
    button.dataset.clearAppCache = "true";
    button.innerHTML = '<ion-icon name="refresh-circle-outline"></ion-icon><div><h3>清理软件缓存</h3><p>清除旧版界面文件并重新加载</p></div><ion-icon name="chevron-forward-outline"></ion-icon>';
    button.addEventListener("click", clearAppCache);
    const logout = [...list.querySelectorAll("button")].find((item) => item.textContent.includes("退出登录"));
    logout ? list.insertBefore(button, logout) : list.appendChild(button);
  }

  new MutationObserver(install).observe(document.documentElement, { childList: true, subtree: true });
  addEventListener("popstate", install);
  install();
})();
