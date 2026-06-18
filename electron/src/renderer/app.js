// Prism renderer entry point: wires the toolbar, tabs, <webview> browsing,
// the 3D backdrop, the start-page wallpaper, the Settings modal and the
// multi-provider AI sidebar together.

import { createBackdrop } from './scene.js';
import { createWallpaper, WALLPAPERS } from './wallpaper.js';
import { loadModelFromFile } from './model3mf.js';
import { AIController, PROVIDERS } from './ai.js';

const $ = (id) => document.getElementById(id);

// ---- Persisted UI preferences (keys are kept in memory only) ----

function loadStore(key, fallback) {
  try { return { ...fallback, ...JSON.parse(localStorage.getItem(key) || '{}') }; }
  catch { return { ...fallback }; }
}
const wallStore = loadStore('prism.wallpaper', { preset: 'icospheres', colorA: '#59f2ff', colorB: '#ff59d9' });
const prefStore = loadStore('prism.prefs', { provider: 'claude', models: {} });

function saveWall() { localStorage.setItem('prism.wallpaper', JSON.stringify(wallStore)); }
function savePrefs() { localStorage.setItem('prism.prefs', JSON.stringify({ provider: ai.provider, models: ai.models })); }

function applyAccent(a, b) {
  document.documentElement.style.setProperty('--neon', a);
  document.documentElement.style.setProperty('--neon-pink', b);
}

// ---- 3D backdrop + start-page wallpaper ----

const backdrop = createBackdrop($('scene'));
const wallpaper = createWallpaper($('wallpaper'), wallStore);
applyAccent(wallStore.colorA, wallStore.colorB);

// ---- Browser (tabs + webviews + start page) ----

function canGo(wv, dir) {
  try { return dir === 'back' ? wv.canGoBack() : wv.canGoForward(); }
  catch { return false; }
}
function escapeHtml(s) {
  return String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
}

class Browser {
  constructor() {
    this.tabs = [];
    this.activeId = null;
    this.content = $('content');
    this.tabsEl = $('tabs');
    this.newTab();
  }

  get active() { return this.tabs.find((t) => t.id === this.activeId); }

  newTab(url) {
    const tab = { id: crypto.randomUUID(), url: url || '', title: 'New Tab', loading: false, webview: null };
    this.tabs.push(tab);
    this.activeId = tab.id;
    if (url) this.go(url, tab);
    this.render();
  }

  ensureWebview(tab) {
    if (tab.webview) return tab.webview;
    const wv = document.createElement('webview');
    wv.setAttribute('allowpopups', 'true');
    wv.classList.add('hidden');
    wv.addEventListener('page-title-updated', (e) => { tab.title = e.title; this.renderTabs(); });
    wv.addEventListener('did-start-loading', () => { tab.loading = true; this.renderTabs(); this.updateToolbar(); });
    wv.addEventListener('did-stop-loading', () => { tab.loading = false; this.renderTabs(); this.updateToolbar(); });
    const onNav = (e) => {
      if (e.url) tab.url = e.url;
      if (tab.id === this.activeId) $('address').value = tab.url;
      this.updateToolbar();
    };
    wv.addEventListener('did-navigate', onNav);
    wv.addEventListener('did-navigate-in-page', (e) => { if (e.isMainFrame) onNav(e); });
    tab.webview = wv;
    this.content.appendChild(wv);
    return wv;
  }

  go(input, tab) {
    tab = tab || this.active;
    if (!tab) return;
    const trimmed = (input || '').trim();
    if (!trimmed) return;
    const looksLikeURL = trimmed.includes('.') && !trimmed.includes(' ');
    const target = looksLikeURL
      ? (trimmed.startsWith('http') ? trimmed : 'https://' + trimmed)
      : 'https://duckduckgo.com/?q=' + encodeURIComponent(trimmed);
    tab.url = target;
    this.ensureWebview(tab).setAttribute('src', target);
    this.render();
  }

  closeTab(id) {
    const i = this.tabs.findIndex((t) => t.id === id);
    if (i < 0) return;
    const [tab] = this.tabs.splice(i, 1);
    if (tab.webview) tab.webview.remove();
    if (this.activeId === id) this.activeId = (this.tabs[this.tabs.length - 1] || {}).id || null;
    if (this.tabs.length === 0) this.newTab();
    else this.render();
  }

  select(id) { this.activeId = id; this.render(); }
  goBack() { const t = this.active; if (t && t.webview && canGo(t.webview, 'back')) t.webview.goBack(); }
  goForward() { const t = this.active; if (t && t.webview && canGo(t.webview, 'forward')) t.webview.goForward(); }
  reload() { const t = this.active; if (t && t.webview) t.webview.reload(); }

  async readPage() {
    const t = this.active;
    if (!t || !t.webview) return '';
    try { return await t.webview.executeJavaScript('document.body.innerText'); }
    catch { return ''; }
  }

  render() { this.renderTabs(); this.renderContent(); this.updateToolbar(); }

  renderContent() {
    const t = this.active;
    const isHome = !t || !t.url;
    $('startpage').classList.toggle('hidden', !isHome);
    for (const tb of this.tabs) {
      if (tb.webview) tb.webview.classList.toggle('hidden', tb.id !== this.activeId || !tb.url);
    }
    if (t) $('address').value = t.url || '';
  }

  renderTabs() {
    this.tabsEl.innerHTML = '';
    for (const t of this.tabs) {
      const el = document.createElement('div');
      el.className = 'tab' + (t.id === this.activeId ? ' active' : '');
      const icon = t.loading ? '<span class="spinner"></span>' : '<span>\u{1F310}</span>';
      el.innerHTML = `${icon}<span class="tab-title">${escapeHtml(t.title || 'New Tab')}</span><button class="tab-close">✕</button>`;
      el.addEventListener('click', (e) => { if (!e.target.classList.contains('tab-close')) this.select(t.id); });
      el.querySelector('.tab-close').addEventListener('click', (e) => { e.stopPropagation(); this.closeTab(t.id); });
      this.tabsEl.appendChild(el);
    }
  }

  updateToolbar() {
    const t = this.active;
    $('btn-back').disabled = !(t && t.webview && canGo(t.webview, 'back'));
    $('btn-forward').disabled = !(t && t.webview && canGo(t.webview, 'forward'));
    const p = $('progress');
    if (t && t.loading) { p.classList.add('active'); p.style.width = '70%'; }
    else { p.style.width = '100%'; setTimeout(() => { p.classList.remove('active'); p.style.width = '0%'; }, 220); }
  }
}

const browser = new Browser();

// ---- AI sidebar ----

const ai = new AIController(
  { go: (u) => browser.go(u), newTab: (u) => browser.newTab(u), readPage: () => browser.readPage(), goBack: () => browser.goBack() },
  renderMessage,
  setThinking
);
if (prefStore.provider) ai.provider = prefStore.provider;
Object.assign(ai.models, prefStore.models || {});

const messagesEl = $('messages');
let thinkingEl = null;

function renderMessage(msg) {
  const el = document.createElement('div');
  el.className = 'bubble ' + msg.role;
  el.textContent = msg.text;
  messagesEl.appendChild(el);
  messagesEl.scrollTop = messagesEl.scrollHeight;
}
function setThinking(on) {
  if (on && !thinkingEl) {
    thinkingEl = document.createElement('div');
    thinkingEl.className = 'thinking';
    thinkingEl.textContent = 'thinking…';
    messagesEl.appendChild(thinkingEl);
    messagesEl.scrollTop = messagesEl.scrollHeight;
  } else if (!on && thinkingEl) {
    thinkingEl.remove();
    thinkingEl = null;
  }
}
renderMessage({ role: 'assistant', text: 'I’m the Prism agent. Pick a provider and paste its API key in Settings, then give me a goal — e.g. "open Hacker News and summarize the top story."' });

const draft = $('draft');
function sendDraft() {
  const text = draft.value;
  draft.value = '';
  draft.style.height = 'auto';
  ai.send(text);
}
$('btn-send').addEventListener('click', sendDraft);
draft.addEventListener('keydown', (e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); sendDraft(); } });
draft.addEventListener('input', () => { draft.style.height = 'auto'; draft.style.height = Math.min(draft.scrollHeight, 96) + 'px'; });
$('agent-mode').addEventListener('change', (e) => { ai.agentMode = e.target.checked; });

// ---- Toolbar + address wiring ----

$('btn-back').addEventListener('click', () => browser.goBack());
$('btn-forward').addEventListener('click', () => browser.goForward());
$('btn-reload').addEventListener('click', () => browser.reload());
$('btn-newtab').addEventListener('click', () => browser.newTab());
$('address').addEventListener('keydown', (e) => { if (e.key === 'Enter') browser.go($('address').value); });
$('start-address').addEventListener('keydown', (e) => { if (e.key === 'Enter') { browser.go($('start-address').value); $('start-address').value = ''; } });
$('btn-ai').addEventListener('click', () => $('sidebar').classList.toggle('collapsed'));

// ---- Settings modal ----

const providerSel = $('provider');
providerSel.value = ai.provider;

function syncProviderFields() {
  const p = PROVIDERS[ai.provider];
  $('key-label').textContent = `${p.name} API key`;
  $('apikey').placeholder = p.envHint;
  $('apikey').value = ai.keys[ai.provider] || '';
  $('model').placeholder = p.defaultModel;
  $('model').value = ai.models[ai.provider] || '';
}
providerSel.addEventListener('change', () => { ai.provider = providerSel.value; syncProviderFields(); savePrefs(); });
$('apikey').addEventListener('input', (e) => { ai.keys[ai.provider] = e.target.value; });
$('model').addEventListener('input', (e) => { ai.models[ai.provider] = e.target.value; savePrefs(); });

$('btn-settings').addEventListener('click', () => { syncProviderFields(); $('settings-overlay').classList.remove('hidden'); });
$('btn-close-settings').addEventListener('click', () => $('settings-overlay').classList.add('hidden'));
$('settings-overlay').addEventListener('click', (e) => { if (e.target.id === 'settings-overlay') $('settings-overlay').classList.add('hidden'); });

// ---- Wallpaper preset + color controls ----

const presetSel = $('wallpaper-preset');
for (const w of WALLPAPERS) {
  const o = document.createElement('option');
  o.value = w.id; o.textContent = w.name;
  presetSel.appendChild(o);
}
presetSel.value = wallStore.preset;
$('color-a').value = wallStore.colorA;
$('color-b').value = wallStore.colorB;

const presetChips = $('start-presets');
function renderPresetChips() {
  presetChips.innerHTML = '';
  for (const w of WALLPAPERS) {
    const chip = document.createElement('div');
    chip.className = 'preset-chip' + (w.id === wallStore.preset ? ' active' : '');
    chip.textContent = w.name;
    chip.addEventListener('click', () => setPreset(w.id));
    presetChips.appendChild(chip);
  }
}
function setPreset(id) {
  wallStore.preset = id;
  presetSel.value = id;
  wallpaper.setPreset(id);
  renderPresetChips();
  saveWall();
}
presetSel.addEventListener('change', () => setPreset(presetSel.value));
$('color-a').addEventListener('input', (e) => {
  wallStore.colorA = e.target.value;
  wallpaper.setColors(wallStore.colorA, null);
  applyAccent(wallStore.colorA, wallStore.colorB);
  saveWall();
});
$('color-b').addEventListener('input', (e) => {
  wallStore.colorB = e.target.value;
  wallpaper.setColors(null, wallStore.colorB);
  applyAccent(wallStore.colorA, wallStore.colorB);
  saveWall();
});
renderPresetChips();

// ---- .3mf model loading (toolbar cube + Settings) ----

const fileInput = $('file-3mf');
$('btn-cube').addEventListener('click', () => fileInput.click());
$('btn-load-3mf').addEventListener('click', () => fileInput.click());
$('btn-reset-3mf').addEventListener('click', () => { backdrop.reset(); $('scene-status').textContent = 'Default: wireframe icosahedron'; });
fileInput.addEventListener('change', async (e) => {
  const file = e.target.files[0];
  if (!file) return;
  $('scene-status').textContent = `Loading ${file.name}…`;
  try {
    const node = await loadModelFromFile(file);
    backdrop.setCustom(node);
    $('scene-status').textContent = `Loaded ${file.name}`;
  } catch (err) {
    $('scene-status').textContent = `⚠︎ ${err.message || err}`;
  }
  fileInput.value = '';
});

syncProviderFields();
