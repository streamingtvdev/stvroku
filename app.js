/**
 * StreamingTV Playlist Setup (Cloudflare Pages)
 *
 * Flow:
 *  1. User enters MAC + PIN shown on the TV
 *  2. Types XC / M3U details
 *  3. We AES-256-CBC encrypt in this browser (key = SHA256(pin:mac))
 *  4. Server stores only ciphertext; TV decrypts locally
 *
 * Set API_BASE to your API origin before deploying.
 */
const API_BASE = "https://api.pirateking.cloud";

const state = {
  mac: "",
  pin: "",
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

function normalizeMac(mac) {
  return String(mac || "").trim().toUpperCase().replace(/[^0-9A-F]/g, "");
}

function formatMac(mac) {
  const n = normalizeMac(mac);
  return (n.match(/.{1,2}/g) || []).join(":");
}

async function api(path, { method = "GET", body } = {}) {
  const headers = { "Content-Type": "application/json" };
  const res = await fetch(API_BASE + path, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });
  let data = null;
  try { data = await res.json(); } catch (_) { /* empty */ }
  if (!res.ok) {
    const detail = (data && (data.detail || data.error || data.message)) || res.statusText;
    const err = new Error(typeof detail === "string" ? detail : JSON.stringify(detail));
    err.status = res.status;
    throw err;
  }
  return data;
}

// --- E2EE helpers (must match the TV: AES-256-CBC, key = SHA256(pin:mac)) ---

async function deriveAesKey(pin, mac) {
  const enc = new TextEncoder();
  const material = await crypto.subtle.digest("SHA-256", enc.encode(pin + ":" + mac));
  return crypto.subtle.importKey("raw", material, { name: "AES-CBC" }, false, ["encrypt", "decrypt"]);
}

function b64(buf) {
  const bytes = buf instanceof ArrayBuffer ? new Uint8Array(buf) : buf;
  let s = "";
  bytes.forEach((b) => { s += String.fromCharCode(b); });
  return btoa(s);
}

function unb64(str) {
  const bin = atob(str);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

async function encryptPayload(pin, mac, obj) {
  const key = await deriveAesKey(pin, mac);
  const iv = crypto.getRandomValues(new Uint8Array(16));
  const plain = new TextEncoder().encode(JSON.stringify(obj));
  const cipher = await crypto.subtle.encrypt({ name: "AES-CBC", iv }, key, plain);
  return { iv: b64(iv), ciphertext: b64(cipher) };
}

async function pinHash(pin, mac) {
  // Must match the TV + API: hex(SHA256(pin + ":" + mac))
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(pin + ":" + mac));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

// --- UI ---

function enterEditor() {
  show($("viewCode"), false);
  show($("viewEditor"), true);
  show($("btnSignOut"), true);
  $("macChip").textContent = "MAC " + formatMac(state.mac);
  $("deviceName").textContent = "This TV";
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
    const isM3u = p.kind === "m3u";
    div.innerHTML = `
      <div class="head">
        <input data-idx="${idx}" data-key="name" value="${escapeAttr(p.name || "My Playlist")}" style="max-width:280px" />
        <div class="row">
          <select data-idx="${idx}" data-key="kind" style="width:120px">
            <option value="xc" ${!isM3u ? "selected" : ""}>XC</option>
            <option value="m3u" ${isM3u ? "selected" : ""}>M3U</option>
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
          <label>${isM3u ? "M3U playlist URL" : "Server URL (http://host:port)"}</label>
          <input data-idx="${idx}" data-key="${isM3u ? "m3u_url" : "server_url"}"
                 value="${escapeAttr(isM3u ? (p.m3u_url || "") : (p.server_url || ""))}"
                 placeholder="${isM3u ? "https://example.com/playlist.m3u" : "http://my-provider.com:8080"}" />
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
  const mac = normalizeMac($("macInput").value);
  const pin = $("pinInput").value.trim().replace(/\s+/g, "");
  if (mac.length < 12) {
    showError($("codeError"), "Enter the full MAC address from the TV.");
    return;
  }
  if (pin.length < 4) {
    showError($("codeError"), "Enter the PIN shown on the TV.");
    return;
  }

  try {
    await api("/api/player/verify", {
      method: "POST",
      body: {
        mac_address: mac,
        pin: pin,
      },
    });
    state.mac = mac;
    state.pin = pin;

    // Check localStorage for previously saved playlists on this device
    let saved = null;
    try {
      const raw = localStorage.getItem("playlists_" + mac);
      if (raw) saved = JSON.parse(raw);
    } catch (_) { /* ignore */ }

    if (Array.isArray(saved) && saved.length > 0) {
      state.playlists = saved;
    } else {
      state.playlists = [{ name: "My Playlist", kind: "xc", server_url: "", username: "", password: "", epg_url: "", enabled: true, sort_order: 0 }];
    }
    enterEditor();
  } catch (err) {
    showError($("codeError"), err.message || "Could not link to this device.");
  }
});

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
    if (!state.playlists.length) {
      showError($("editorError"), "Add at least one playlist.");
      return;
    }
    for (const p of state.playlists) {
      if (p.kind === "m3u" && !(p.m3u_url || "").trim()) {
        showError($("editorError"), "Every M3U playlist needs a URL.");
        return;
      }
      if (p.kind !== "m3u" && !(p.server_url || "").trim()) {
        showError($("editorError"), "Every XC playlist needs a server URL.");
        return;
      }
    }

    // One payload the TV decrypts and applies (array of playlists)
    const payload = state.playlists.map((p, i) => ({
      name: p.name || "Playlist",
      kind: p.kind || "xc",
      server_url: (p.server_url || "").trim(),
      m3u_url: (p.m3u_url || "").trim(),
      epg_url: (p.epg_url || "").trim(),
      username: p.username || "",
      password: p.password || "",
      enabled: p.enabled !== false,
      sort_order: i,
    }));

    const { iv, ciphertext } = await encryptPayload(state.pin, state.mac, payload);
    await api("/api/player/submit", {
      method: "POST",
      body: {
        mac_address: state.mac,
        pin: state.pin,
        iv,
        ciphertext,
      },
    });

    try {
      localStorage.setItem("playlists_" + state.mac, JSON.stringify(payload));
    } catch (_) { /* ignore */ }

    $("editorOk").textContent = "Saved. Your TV will pick this up automatically (give it a few seconds).";
    show($("editorOk"), true);
  } catch (err) {
    if (err.status === 404 || err.status === 410) {
      showError($("editorError"), err.message + " Hold * on the TV to get a new PIN.");
      return;
    }
    showError($("editorError"), err.message || "Save failed.");
  }
});

$("btnReload").addEventListener("click", () => {
  let saved = null;
  try {
    const raw = localStorage.getItem("playlists_" + state.mac);
    if (raw) saved = JSON.parse(raw);
  } catch (_) { /* ignore */ }

  if (Array.isArray(saved) && saved.length > 0) {
    state.playlists = saved;
    renderList();
    showError($("editorError"), "");
    $("editorOk").textContent = "Playlists reloaded from local storage.";
    show($("editorOk"), true);
  } else {
    showError($("editorError"), "No saved local cache found. Hold * on the TV for a new PIN to re-enter credentials.");
  }
});

$("btnUnbind").addEventListener("click", async () => {
  if (!confirm("Remove this MAC from the system? The TV will need setup again.")) return;
  try {
    await api("/api/player/unbind", {
      method: "POST",
      body: { mac_address: state.mac, pin: state.pin },
    });
    try {
      localStorage.removeItem("playlists_" + state.mac);
    } catch (_) { /* ignore */ }
    signOut();
    showError($("codeError"), "MAC removed from system.");
  } catch (err) {
    showError($("editorError"), err.message || "Could not remove device.");
  }
});

function signOut() {
  state.mac = "";
  state.pin = "";
  state.playlists = [];
  enterCodeView();
}
$("btnSignOut").addEventListener("click", signOut);

enterCodeView();

// Prefill from QR / shared link: ?mac=AABBCCDDEEFF&code=123456
(function prefillFromQuery() {
  try {
    const q = new URLSearchParams(location.search);
    const mac = q.get("mac") || q.get("device") || "";
    const code = q.get("code") || q.get("pin") || "";
    if (mac) $("macInput").value = formatMac(mac);
    if (code) $("pinInput").value = code;
  } catch (_) { /* ignore */ }
})();
