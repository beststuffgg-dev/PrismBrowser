// Bridges a minimal, safe API into the renderer. Only the network proxy is
// exposed — everything else (browsing, 3D, AI orchestration) lives in the
// renderer with context isolation on.

const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('prism', {
  /**
   * Perform an HTTP request from the main process (no CORS).
   * @param {{url:string, method?:string, headers?:object, body?:string}} opts
   * @returns {Promise<{ok:boolean, status:number, body:string}>}
   */
  netFetch: (opts) => ipcRenderer.invoke('net:fetch', opts)
});
