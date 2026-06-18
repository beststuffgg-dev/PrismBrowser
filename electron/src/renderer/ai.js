// Multi-provider agentic AI, ported from AIController.swift + AIProvider.swift.
//
// Supports Claude (Anthropic Messages), ChatGPT/Perplexity/DeepSeek (OpenAI
// chat-completions) and Gemini (generateContent). Keeps a normalized history,
// runs a capped tool loop, and drives the browser via injected callbacks.
// All HTTP goes through window.prism.netFetch (main process) to avoid CORS.

export const PROVIDERS = {
  claude:     { name: 'Claude',     style: 'anthropic', defaultModel: 'claude-sonnet-4-5', envHint: 'sk-ant-…', supportsTools: true },
  chatgpt:    { name: 'ChatGPT',    style: 'openai',    defaultModel: 'gpt-4o',             endpoint: 'https://api.openai.com/v1/chat/completions',  envHint: 'sk-…',   supportsTools: true },
  gemini:     { name: 'Gemini',     style: 'gemini',    defaultModel: 'gemini-2.0-flash',   envHint: 'AIza…',  supportsTools: true },
  perplexity: { name: 'Perplexity', style: 'openai',    defaultModel: 'sonar',              endpoint: 'https://api.perplexity.ai/chat/completions', envHint: 'pplx-…', supportsTools: false },
  deepseek:   { name: 'DeepSeek',   style: 'openai',    defaultModel: 'deepseek-chat',      endpoint: 'https://api.deepseek.com/chat/completions',  envHint: 'sk-…',   supportsTools: true }
};

const SYSTEM_PROMPT =
  "You are Prism's built-in browsing agent. Be concise. Use the provided tools " +
  "to navigate and read pages when the user asks you to act on the web. Summarize what you find.";

const TOOL_DEFS = [
  { name: 'navigate', description: 'Load a URL or web search in the current tab.',
    parameters: { type: 'object', properties: { url: { type: 'string' } }, required: ['url'] } },
  { name: 'open_tab', description: 'Open a new browser tab, optionally at a URL.',
    parameters: { type: 'object', properties: { url: { type: 'string' } } } },
  { name: 'read_page', description: 'Return the visible text of the current page.',
    parameters: { type: 'object', properties: {} } },
  { name: 'go_back', description: 'Navigate back in history.',
    parameters: { type: 'object', properties: {} } }
];

export class AIController {
  /**
   * @param {object} browser  { go, newTab, readPage, goBack }
   * @param {(msg)=>void} onMessage  called with {role, text} to render
   * @param {(thinking:boolean)=>void} onThinking
   */
  constructor(browser, onMessage, onThinking) {
    this.browser = browser;
    this.onMessage = onMessage;
    this.onThinking = onThinking;

    this.provider = 'claude';
    this.agentMode = true;
    this.keys = {};
    this.models = {};
    for (const id of Object.keys(PROVIDERS)) this.models[id] = PROVIDERS[id].defaultModel;

    // Plain history of {role:'user'|'assistant', text} for context rebuilds.
    this.transcript = [];
  }

  currentKey() { return this.keys[this.provider] || ''; }
  currentModel() { return this.models[this.provider] || PROVIDERS[this.provider].defaultModel; }

  async send(userText) {
    const text = (userText || '').trim();
    if (!text) return;
    this.transcript.push({ role: 'user', text });
    this.onMessage({ role: 'user', text });

    if (!this.currentKey()) {
      this.onMessage({ role: 'system', text: `No API key set for ${PROVIDERS[this.provider].name}. Open Settings (⚙), choose a provider and paste its key.` });
      return;
    }
    await this.runAgentLoop();
  }

  async runAgentLoop() {
    this.onThinking(true);
    try {
      // Normalized history: start on a user turn (Anthropic/Gemini require it).
      const history = [];
      for (const m of this.transcript) {
        if (m.role === 'user') history.push({ type: 'user', text: m.text });
        else if (m.role === 'assistant' && history.length) history.push({ type: 'assistant', text: m.text, toolCalls: [] });
      }

      for (let i = 0; i < 6; i++) {
        const resp = await this.callProvider(history);
        if (resp.text) {
          this.transcript.push({ role: 'assistant', text: resp.text });
          this.onMessage({ role: 'assistant', text: resp.text });
        }
        const useTools = this.agentMode && PROVIDERS[this.provider].supportsTools;
        if (!useTools || resp.toolCalls.length === 0) return;

        history.push({ type: 'assistant', text: resp.text, toolCalls: resp.toolCalls });
        const results = [];
        for (const call of resp.toolCalls) {
          const summary = Object.entries(call.arguments).map(([k, v]) => `${k}=${v}`).join(', ');
          this.onMessage({ role: 'tool', text: `→ ${call.name}(${summary})` });
          const out = await this.runTool(call);
          results.push({ id: call.id, name: call.name, content: out });
        }
        history.push({ type: 'toolResults', results });
      }
    } catch (err) {
      this.onMessage({ role: 'system', text: `⚠︎ ${PROVIDERS[this.provider].name} error: ${err.message || err}` });
    } finally {
      this.onThinking(false);
    }
  }

  async runTool(call) {
    const b = this.browser;
    switch (call.name) {
      case 'navigate':
        b.go(call.arguments.url || '');
        await sleep(1800);
        return `Navigated to ${call.arguments.url || ''}.`;
      case 'open_tab':
        b.newTab(call.arguments.url);
        return `Opened a new tab${call.arguments.url ? ' at ' + call.arguments.url : ''}.`;
      case 'read_page':
        return (await b.readPage()).slice(0, 8000);
      case 'go_back':
        b.goBack();
        return 'Went back.';
      default:
        return `Unknown tool ${call.name}.`;
    }
  }

  // ---- Provider dispatch ----

  async callProvider(history) {
    const p = PROVIDERS[this.provider];
    const useTools = this.agentMode && p.supportsTools;
    if (p.style === 'anthropic') return this.callAnthropic(history, useTools);
    if (p.style === 'gemini')    return this.callGemini(history, useTools);
    return this.callOpenAI(history, useTools);
  }

  async fetchJSON(url, headers, bodyObj) {
    const res = await window.prism.netFetch({
      url, method: 'POST',
      headers: { 'Content-Type': 'application/json', ...headers },
      body: JSON.stringify(bodyObj)
    });
    if (!res.ok) throw new Error(res.body || `status ${res.status}`);
    try { return JSON.parse(res.body); }
    catch { throw new Error('Malformed response'); }
  }

  // Anthropic (Claude)
  async callAnthropic(history, useTools) {
    const body = {
      model: this.currentModel(),
      max_tokens: 1024,
      system: SYSTEM_PROMPT,
      messages: history.map((item) => {
        if (item.type === 'user') return { role: 'user', content: item.text };
        if (item.type === 'assistant') {
          const content = [];
          if (item.text) content.push({ type: 'text', text: item.text });
          for (const c of item.toolCalls) content.push({ type: 'tool_use', id: c.id, name: c.name, input: c.arguments });
          return { role: 'assistant', content };
        }
        return { role: 'user', content: item.results.map((r) => ({ type: 'tool_result', tool_use_id: r.id, content: r.content })) };
      })
    };
    if (useTools) body.tools = TOOL_DEFS.map((t) => ({ name: t.name, description: t.description, input_schema: t.parameters }));

    const json = await this.fetchJSON('https://api.anthropic.com/v1/messages', {
      'x-api-key': this.currentKey(), 'anthropic-version': '2023-06-01'
    }, body);

    let text = '';
    const toolCalls = [];
    for (const block of json.content || []) {
      if (block.type === 'text') text += block.text || '';
      else if (block.type === 'tool_use') toolCalls.push({ id: block.id || '', name: block.name || '', arguments: block.input || {} });
    }
    return { text, toolCalls };
  }

  // OpenAI-compatible (ChatGPT / Perplexity / DeepSeek)
  async callOpenAI(history, useTools) {
    const messages = [{ role: 'system', content: SYSTEM_PROMPT }];
    for (const item of history) {
      if (item.type === 'user') messages.push({ role: 'user', content: item.text });
      else if (item.type === 'assistant') {
        const m = { role: 'assistant', content: item.text || '' };
        if (item.toolCalls.length) {
          m.tool_calls = item.toolCalls.map((c) => ({
            id: c.id, type: 'function',
            function: { name: c.name, arguments: JSON.stringify(c.arguments) }
          }));
        }
        messages.push(m);
      } else {
        for (const r of item.results) messages.push({ role: 'tool', tool_call_id: r.id, content: r.content });
      }
    }
    const body = { model: this.currentModel(), max_tokens: 1024, messages };
    if (useTools) {
      body.tools = TOOL_DEFS.map((t) => ({ type: 'function', function: { name: t.name, description: t.description, parameters: t.parameters } }));
      body.tool_choice = 'auto';
    }

    const json = await this.fetchJSON(PROVIDERS[this.provider].endpoint, {
      Authorization: `Bearer ${this.currentKey()}`
    }, body);

    const msg = (json.choices && json.choices[0] && json.choices[0].message) || {};
    const toolCalls = (msg.tool_calls || []).map((tc) => {
      let args = {};
      try { args = JSON.parse(tc.function.arguments || '{}'); } catch { /* ignore */ }
      return { id: tc.id || crypto.randomUUID(), name: tc.function.name || '', arguments: args };
    });
    return { text: msg.content || '', toolCalls };
  }

  // Gemini (Google)
  async callGemini(history, useTools) {
    const contents = history.map((item) => {
      if (item.type === 'user') return { role: 'user', parts: [{ text: item.text }] };
      if (item.type === 'assistant') {
        const parts = [];
        if (item.text) parts.push({ text: item.text });
        for (const c of item.toolCalls) parts.push({ functionCall: { name: c.name, args: c.arguments } });
        return { role: 'model', parts };
      }
      return { role: 'user', parts: item.results.map((r) => ({ functionResponse: { name: r.name, response: { result: r.content } } })) };
    });
    const body = {
      contents,
      systemInstruction: { parts: [{ text: SYSTEM_PROMPT }] },
      generationConfig: { maxOutputTokens: 1024 }
    };
    if (useTools) body.tools = [{ functionDeclarations: TOOL_DEFS.map((t) => ({ name: t.name, description: t.description, parameters: t.parameters })) }];

    const url = `https://generativelanguage.googleapis.com/v1beta/models/${this.currentModel()}:generateContent?key=${this.currentKey()}`;
    const json = await this.fetchJSON(url, {}, body);

    const parts = (json.candidates && json.candidates[0] && json.candidates[0].content && json.candidates[0].content.parts) || [];
    let text = '';
    const toolCalls = [];
    for (const part of parts) {
      if (part.text) text += part.text;
      if (part.functionCall) toolCalls.push({ id: part.functionCall.name, name: part.functionCall.name, arguments: part.functionCall.args || {} });
    }
    return { text, toolCalls };
  }
}

function sleep(ms) { return new Promise((r) => setTimeout(r, ms)); }
