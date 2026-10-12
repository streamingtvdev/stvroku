/**
 * StreamingTV Playlist Editor (Cloudflare Pages)
 * Talks to the KING API: /api/editor/redeem and /api/editor/playlists
 * Set API_BASE to your API origin before deploying.
 */
const API_BASE = "https://api.pirateking.cloud";

const state = {
  session: localStorage.getItem("stv_editor_session") || "",
  deviceName: localStorage.getItem("stv_editor_device") || "",
  mac: localStorage.getItem("stv_editor_mac") || "",
  playlists: [],
};

const $ = (id) => document.getElementById(id);

function show(el, on = true) {
  el.classList.toggle("hidden", !on);
}

function showError(el, msg) {
  if (!msg) { show(el, false); el.textContent = ""; return; }
  el.textContent = msg;
  show(el, true);
}

async function api(path, { method = "GET", body, session = true } = {}) {
  const headers = { "Content-Type": "application/json" };
  if (session && state.session) headers["X-Editor-Session"] = state.session;
  const res = await fetch(API_BASE + path, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });
  let data = null;
  try { data = await res.json(); } catch (_) { /* empty */ }
  if (!res.ok) {
    const detail = (data && (data.detail || data.error)) || res.statusText;
    const err = new Error(typeof detail === "string" ? detail : JSON.stringify(detail));
    err.status = res.status;
    throw err;
  }
  return data;
}

function enterEditor() {
  show($("viewCode"), false);
  show($("viewEditor"), true);
  show($("btnSignOut"), true);
  $("deviceName").textContent = state.deviceName || "Device";
  $("macChip").textContent = "MAC " + (state.mac || "—");
  renderList();
}

function enterCodeView() {
  show($("viewCode"), true);
  show($("viewEditor"), false);
  show($("btnSignOut"), false);
}

function renderList() {
  const root = $("playlistList");
  root.innerHTML = "";
  if (!state.playlists.length) {
    root.innerHTML = `<div class="item muted">No playlists yet. Add an XC or M3U playlist below.</div>`;
    return;
  }

  state.playlists.forEach((p, idx) => {
    const div = document.createElement("div");
    div.className = "item";
    div.innerHTML = `
      <div class="head">
        <input data-idx="${idx}" data-key="name" value="${escapeAttr(p.name || "My Playlist")}" style="max-width:280px" />
        <div class="row">
          <select data-idx="${idx}" data-key="kind" style="width:120px">
            <option value="xc" ${p.kind === "xc" ? "selected" : ""}>XC</option>
            <option value="m3u" ${p.kind === "m3u" ? "selected" : ""}>M3U</option>
          </select>
          <label class="row" style="margin:0;gap:6px;font-size:13px">
            <input type="checkbox" data-idx="${idx}" data-key="enabled" ${p.enabled !== false ? "checked" : ""} style="width:auto" />
            On
          </label>
          <button class="danger" data-remove="${idx}" type="button">Remove</button>
        </div>
      </div>
      <div class="fields">
        <div class="full">
          <label>${p.kind === "m3u" ? "M3U playlist URL" : "Server URL (http://host:port)"}</label>
          <input data-idx="${idx}" data-key="${p.kind === "m3u" ? "m3u_url" : "server_url"}"
                 value="${escapeAttr(p.kind === "m3u" ? (p.m3u_url || "") : (p.server_url || ""))}"
                 placeholder="${p.kind === "m3u" ? "https://example.com/playlist.m3u" : "http://my-provider.com:8080"}" />
        </div>
        <div>
          <label>Username</label>
          <input data-idx="${idx}" data-key="username" value="${escapeAttr(p.username || "")}" autocomplete="off" />
        </div>
        <div>
          <label>Password</label>
          <input data-idx="${idx}" data-key="password" type="password" value="${escapeAttr(p.password || "")}" autocomplete="off" />
        </div>
        <div class="full">
          <label>EPG URL (optional)</label>
          <input data-idx="${idx}" data-key="epg_url" value="${escapeAttr(p.epg_url || "")}" placeholder="http://host/xmltv.php" />
        </div>
      </div>
    `;
    root.appendChild(div);
  });

  root.querySelectorAll("input,select").forEach((el) => {
    el.addEventListener("change", () => {
      const idx = Number(el.dataset.idx);
      const key = el.dataset.key;
      if (key === "enabled") state.playlists[idx].enabled = el.checked;
      else state.playlists[idx][key] = el.value;
      if (key === "kind") renderList();
    });
  });
  root.querySelectorAll("[data-remove]").forEach((btn) => {
    btn.addEventListener("click", () => {
      state.playlists.splice(Number(btn.dataset.remove), 1);
      renderList();
    });
  });
}

function escapeAttr(v) {
  return String(v).replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;");
}

$("formCode").addEventListener("submit", async (e) => {
  e.preventDefault();
  showError($("codeError"), "");
  const code = $("codeInput").value.trim();
  try {
    const data = await api("/api/editor/redeem", {
      method: "POST",
      session: false,
      body: { code, mac_address: null },
    });
    state.session = data.session_token;
    state.deviceName = data.device_name || "Device";
    state.mac = data.mac_address || "";
    localStorage.setItem("stv_editor_session", state.session);
    localStorage.setItem("stv_editor_device", state.deviceName);
    localStorage.setItem("stv_editor_mac", state.mac);
    await loadPlaylists();
    enterEditor();
  } catch (err) {
    showError($("codeError"), err.message || "Could not use that code.");
  }
});

async function loadPlaylists() {
  const data = await api("/api/editor/playlists");
  state.playlists = (data.playlists || []).map((p) => ({ ...p }));
  state.deviceName = data.device_name || state.deviceName;
  state.mac = data.mac_address || state.mac;
}

$("btnAdd").addEventListener("click", () => {
  state.playlists.push({
    name: "Playlist " + (state.playlists.length + 1),
    kind: "xc",
    server_url: "",
    m3u_url: "",
    username: "",
    password: "",
    epg_url: "",
    enabled: true,
    sort_order: state.playlists.length,
  });
  renderList();
});

$("btnSave").addEventListener("click", async () => {
  showError($("editorError"), "");
  show($("editorOk"), false);
  try {
    const payload = state.playlists.map((p, i) => ({
      name: p.name || "Playlist",
      kind: p.kind || "xc",
      server_url: p.server_url || null,
      m3u_url: p.m3u_url || null,
      epg_url: p.epg_url || null,
      username: p.username || null,
      password: p.password || null,
      enabled: p.enabled !== false,
      sort_order: i,
    }));
    await api("/api/editor/playlists", { method: "PUT", body: payload });
    $("editorOk").textContent = "Saved. Your TV will pick up changes the next time it loads a list.";
    show($("editorOk"), true);
    await loadPlaylists();
    renderList();
  } catch (err) {
    if (err.status === 401) {
      signOut();
      showError($("codeError"), "Session expired. Enter a new device code.");
      return;
    }
    showError($("editorError"), err.message || "Save failed.");
  }
});

$("btnReload").addEventListener("click", async () => {
  try {
    await loadPlaylists();
    renderList();
    showError($("editorError"), "");
  } catch (err) {
    showError($("editorError"), err.message || "Reload failed.");
  }
});

function signOut() {
  state.session = "";
  localStorage.removeItem("stv_editor_session");
  localStorage.removeItem("stv_editor_device");
  localStorage.removeItem("stv_editor_mac");
  enterCodeView();
}
$("btnSignOut").addEventListener("click", signOut);

(async function boot() {
  if (state.session) {
    try {
      await loadPlaylists();
      enterEditor();
      return;
    } catch (_) {
      signOut();
    }
  }
  enterCodeView();
})();
