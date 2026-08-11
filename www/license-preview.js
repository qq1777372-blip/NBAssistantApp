(() => {
  const RELEASE = "20260806-license-preview-0845";
  // 列表/详情用压缩图（后端 ?thumb=1，最长边 1280）；全屏和保存仍取原图
  const thumbUrl = (url) => !url ? url : url + (url.indexOf("?") >= 0 ? "&" : "?") + "thumb=1";
  const ROOT_ID = "app-license-image-preview";
  const STYLE_ID = "app-license-image-preview-style";
  const state = { route: "", record: null, loading: false , renderedKey: "", suspend: false };

  function currentLicenseId() {
    const path = location.pathname.replace(/^\/app/, "");
    const match = path.match(/\/tabs\/detail\/licenses\/([^/?#]+)/);
    return match ? decodeURIComponent(match[1]) : "";
  }

  function installStyle() {
    const existing = document.getElementById(STYLE_ID);
    if (existing?.dataset.release === RELEASE) return;
    existing?.remove();
    const style = document.createElement("style");
    style.id = STYLE_ID;
    style.dataset.release = RELEASE;
    style.textContent = `
      #${ROOT_ID}{margin:0 0 16px;padding:12px;border:1px solid var(--app-line,#e5e7eb);border-radius:16px;background:var(--app-card,#fff);box-shadow:0 5px 18px rgba(15,23,42,.06)}
      #${ROOT_ID} .license-preview-head{display:flex;align-items:center;justify-content:space-between;gap:10px;margin-bottom:10px}
      #${ROOT_ID} .license-preview-head strong{font-size:14px;color:var(--app-text,#111827)}
      #${ROOT_ID} .license-preview-head span{color:var(--app-muted,#6b7280);font-size:10px}
      #${ROOT_ID} .license-preview-image{display:block;width:100%;max-height:54vh;object-fit:contain;border:0;border-radius:12px;background:var(--app-soft,#f3f4f6);cursor:zoom-in;-webkit-user-select:none;user-select:none;-webkit-touch-callout:default}
      #${ROOT_ID} .license-preview-actions{display:grid;grid-template-columns:1fr 1fr;gap:9px;margin-top:11px}
      #${ROOT_ID} .license-preview-actions button{height:42px;border:1px solid var(--app-line,#e5e7eb);border-radius:11px;color:var(--app-text,#111827);background:var(--app-card,#fff);font-size:13px;font-weight:600}
      #${ROOT_ID} .license-preview-actions button.primary{border-color:#2563eb;color:#fff;background:#2563eb}
      #${ROOT_ID} .license-preview-tip{display:block;margin-top:8px;color:var(--app-muted,#6b7280);font-size:10px;text-align:center;line-height:1.5}
      #${ROOT_ID} .license-preview-empty{display:grid;place-items:center;min-height:120px;color:var(--app-muted,#6b7280);font-size:12px}
      .license-fullscreen{position:fixed;inset:0;z-index:2147483000;display:grid;grid-template-rows:auto 1fr auto;background:rgba(3,7,18,.96);overscroll-behavior:contain}
      .license-fullscreen-head{display:flex;align-items:center;justify-content:space-between;padding:calc(10px + env(safe-area-inset-top)) 12px 10px;color:#fff}
      .license-fullscreen-head strong{min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size:14px}
      .license-fullscreen-head button,.license-fullscreen-actions button{border:1px solid rgba(255,255,255,.22);border-radius:11px;color:#fff;background:rgba(255,255,255,.1);font-size:13px;font-weight:600}
      .license-fullscreen-head button{width:42px;height:42px;font-size:22px}
      .license-fullscreen-stage{overflow:auto;display:grid;place-items:center;padding:8px;touch-action:pan-x pan-y pinch-zoom}
      .license-fullscreen-stage img{display:block;max-width:none;width:auto;min-width:100%;height:auto;max-height:none;object-fit:contain;-webkit-touch-callout:default}
      .license-fullscreen-actions{padding:10px 12px calc(10px + env(safe-area-inset-bottom));background:linear-gradient(transparent,rgba(3,7,18,.85))}
      .license-fullscreen-actions button{width:100%;height:46px;background:#2563eb;border-color:#2563eb}
      .license-save-toast{position:fixed;z-index:2147483647;right:18px;bottom:calc(22px + env(safe-area-inset-bottom));left:18px;padding:12px 15px;border-radius:12px;text-align:center;color:#fff;background:rgba(17,24,39,.94);font-size:13px;box-shadow:0 8px 28px rgba(0,0,0,.28)}
    `;
    document.head.append(style);
  }

  function toast(message) {
    document.querySelector(".license-save-toast")?.remove();
    const node = document.createElement("div");
    node.className = "license-save-toast";
    node.textContent = message;
    document.body.append(node);
    setTimeout(() => node.remove(), 2200);
  }

  function filename(record) {
    const fromRecord = String(record?.image_name || "").trim();
    if (fromRecord) return fromRecord;
    const subject = String(record?.subject_name || "执照").replace(/[\\/:*?\"<>|]/g, "_");
    return `${subject}.jpg`;
  }

  async function saveImage(record) {
    const url = record?.image_url;
    if (!url) return;
    try {
      toast("正在准备图片…");
      const response = await fetch(url, { credentials: "include", cache: "no-store" });
      if (!response.ok) throw new Error(`下载失败 (${response.status})`);
      const blob = await response.blob();
      const name = filename(record);
      const file = new File([blob], name, { type: blob.type || "image/jpeg" });
      if (navigator.canShare?.({ files: [file] })) {
        await navigator.share({ files: [file], title: record.subject_name || "执照图片" });
        toast("已打开系统保存面板");
        return;
      }
      const objectUrl = URL.createObjectURL(blob);
      const link = document.createElement("a");
      link.href = objectUrl;
      link.download = name;
      link.style.display = "none";
      document.body.append(link);
      link.click();
      link.remove();
      setTimeout(() => URL.revokeObjectURL(objectUrl), 5000);
      toast("图片已开始下载");
    } catch (error) {
      if (error?.name === "AbortError") return;
      toast(error?.message || "保存失败，请长按图片保存");
    }
  }

  function openFullscreen(record) {
    document.querySelector(".license-fullscreen")?.remove();
    const overlay = document.createElement("div");
    overlay.className = "license-fullscreen";

    const head = document.createElement("header");
    head.className = "license-fullscreen-head";
    const title = document.createElement("strong");
    title.textContent = record.subject_name || "执照图片";
    const close = document.createElement("button");
    close.type = "button";
    close.setAttribute("aria-label", "关闭预览");
    close.textContent = "×";
    close.onclick = () => overlay.remove();
    head.append(title, close);

    const stage = document.createElement("div");
    stage.className = "license-fullscreen-stage";
    const image = document.createElement("img");
    image.src = thumbUrl(record.image_url);
    image.alt = record.subject_name || "执照图片";
    image.draggable = false;
    stage.append(image);

    const actions = document.createElement("footer");
    actions.className = "license-fullscreen-actions";
    const save = document.createElement("button");
    save.type = "button";
    save.textContent = "保存图片到本地";
    save.onclick = () => saveImage(record);
    actions.append(save);

    overlay.append(head, stage, actions);
    overlay.onclick = (event) => {
      if (event.target === overlay || event.target === stage) overlay.remove();
    };
    document.body.append(overlay);
  }

  function render(record) {
    const head = document.querySelector(".detail-head");
    if (!head || !head.isConnected) return;
    // 幂等：同一条记录且节点仍在，直接返回。render 挂在 MutationObserver 回调链上，
    // 无条件重建 DOM 会自触发 observer 造成死循环。
    const key = record?.image_url ? String(record.id) + "|" + record.image_url : "empty:" + String(record?.id ?? "");
    const existingRoot = document.getElementById(ROOT_ID);
    if (existingRoot?.isConnected && state.renderedKey === key) return;
    state.suspend = true;
    try {
    let root = existingRoot;
    if (!root || !root.isConnected) {
      root = document.createElement("section");
      root.id = ROOT_ID;
      head.insertAdjacentElement("afterend", root);
    }
    state.renderedKey = key;
    root.replaceChildren();
    if (!record?.image_url) {
      const empty = document.createElement("div");
      empty.className = "license-preview-empty";
      empty.textContent = "该执照暂未上传图片";
      root.append(empty);
      return;
    }

    const header = document.createElement("div");
    header.className = "license-preview-head";
    const title = document.createElement("strong");
    title.textContent = "执照图片";
    const name = document.createElement("span");
    name.textContent = record.image_name || "点击查看大图";
    header.append(title, name);

    const image = document.createElement("img");
    image.className = "license-preview-image";
    image.src = record.image_url;
    image.alt = record.subject_name || "执照图片";
    image.loading = "eager";
    image.onclick = () => openFullscreen(record);

    const actions = document.createElement("div");
    actions.className = "license-preview-actions";
    const preview = document.createElement("button");
    preview.type = "button";
    preview.textContent = "查看大图";
    preview.onclick = () => openFullscreen(record);
    const save = document.createElement("button");
    save.type = "button";
    save.className = "primary";
    save.textContent = "保存图片";
    save.onclick = () => saveImage(record);
    actions.append(preview, save);

    const tip = document.createElement("small");
    tip.className = "license-preview-tip";
    tip.textContent = "也可以长按图片，使用系统菜单保存";
    root.append(header, image, actions, tip);
    } finally {
      // 让本次写入产生的 mutation 记录被丢弃，再恢复观察
      setTimeout(() => { observer.takeRecords(); state.suspend = false; }, 0);
    }
  }

  async function load() {
    const id = currentLicenseId();
    const route = `${location.pathname}${location.search}`;
    if (!id) {
      state.route = "";
      state.record = null;
      state.renderedKey = "";
      document.getElementById(ROOT_ID)?.remove();
      document.querySelector(".license-fullscreen")?.remove();
      return;
    }
    if (state.loading || state.route === route) {
      if (state.record) render(state.record);
      return;
    }
    state.route = route;
    state.loading = true;
    try {
      const response = await fetch("/license-records", { credentials: "include", cache: "no-store" });
      if (!response.ok) throw new Error(`执照加载失败 (${response.status})`);
      const payload = await response.json();
      const rows = Array.isArray(payload) ? payload : payload?.items || [];
      state.record = rows.find((item) => String(item.id) === String(id)) || null;
      render(state.record);
    } catch (error) {
      toast(error?.message || "执照加载失败");
    } finally {
      state.loading = false;
    }
  }

  function mount() {
    if (state.suspend) return;
    installStyle();
    const id = currentLicenseId();
    if (!id) {
      document.getElementById(ROOT_ID)?.remove();
      document.querySelector(".license-fullscreen")?.remove();
      state.route = "";
      state.record = null;
      state.renderedKey = "";
      return;
    }
    if (document.querySelector(".detail-head")) load();
  }

  const observer = new MutationObserver(mount);
  observer.observe(document.documentElement, { childList: true, subtree: true });
  addEventListener("popstate", mount);
  addEventListener("pageshow", mount);
  mount();
})();
