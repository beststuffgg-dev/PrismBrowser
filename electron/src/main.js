// Electron main process for Prism.
//
// Creates the dark, frameless-friendly browser window and exposes a single
// privileged helper to the renderer: a generic HTTP proxy (`net:fetch`). All
// AI-provider traffic is routed through here so the renderer never hits CORS
// (Anthropic/OpenAI/Gemini/etc. reject direct browser-origin requests).

const { app, BrowserWindow, ipcMain } = require('electron');
const path = require('path');

function createWindow() {
  const win = new BrowserWindow({
    width: 1280,
    height: 820,
    minWidth: 1100,
    minHeight: 720,
    backgroundColor: '#0a0d17',
    title: 'Prism',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      webviewTag: true,   // each browser tab is a <webview>
      sandbox: false
    }
  });

  win.loadFile(path.join(__dirname, 'renderer', 'index.html'));
}

app.whenReady().then(() => {
  createWindow();
  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});

// Generic network proxy used by the AI layer. Runs in the main process (Node
// fetch), so it is not subject to browser CORS restrictions.
ipcMain.handle('net:fetch', async (_event, { url, method, headers, body }) => {
  try {
    const res = await fetch(url, {
      method: method || 'POST',
      headers: headers || {},
      body
    });
    const text = await res.text();
    return { ok: res.ok, status: res.status, body: text };
  } catch (err) {
    return { ok: false, status: 0, body: String((err && err.message) || err) };
  }
});
