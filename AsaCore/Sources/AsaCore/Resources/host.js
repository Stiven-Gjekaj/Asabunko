// The web functions that the JavaScript sources expect, on top of the native functions of
// JSRuntime.swift: __native.fetch, __native.decode, __native.timer, and __native.log.
(function () {
  'use strict';
  const native = globalThis.__native;

  // Timers.
  const timers = new Map();
  let nextTimer = 1;
  globalThis.setTimeout = function (fn, ms, ...args) {
    const id = nextTimer++;
    timers.set(id, () => fn(...args));
    native.timer(id, Math.max(0, Number(ms) || 0));
    return id;
  };
  globalThis.clearTimeout = function (id) { timers.delete(id); };
  globalThis.setInterval = function (fn, ms, ...args) {
    const id = nextTimer++;
    const tick = () => { if (!timers.has(id)) return; fn(...args); timers.set(id, tick); native.timer(id, Math.max(10, Number(ms) || 0)); };
    timers.set(id, tick);
    native.timer(id, Math.max(10, Number(ms) || 0));
    return id;
  };
  globalThis.clearInterval = globalThis.clearTimeout;
  globalThis.__timerFire = function (id) {
    const fn = timers.get(id);
    timers.delete(id);
    if (fn) fn();
  };
  globalThis.queueMicrotask = globalThis.queueMicrotask || function (fn) { Promise.resolve().then(fn); };

  // Console.
  const format = (args) => args.map((a) => { try { return typeof a === 'string' ? a : JSON.stringify(a); } catch (e) { return String(a); } }).join(' ');
  globalThis.console = { log: (...a) => native.log(format(a)), info: (...a) => native.log(format(a)), debug: () => {}, warn: (...a) => native.log(format(a)), error: (...a) => native.log(format(a)) };

  // Base64.
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  globalThis.btoa = function (input) {
    const text = String(input);
    let out = '';
    for (let i = 0; i < text.length; i += 3) {
      const a = text.charCodeAt(i), b = text.charCodeAt(i + 1), c = text.charCodeAt(i + 2);
      const n = (a << 16) | ((b || 0) << 8) | (c || 0);
      out += chars[(n >> 18) & 63] + chars[(n >> 12) & 63] + (isNaN(b) ? '=' : chars[(n >> 6) & 63]) + (isNaN(c) ? '=' : chars[n & 63]);
    }
    return out;
  };
  globalThis.atob = function (input) {
    const text = String(input).replace(/[^A-Za-z0-9+/]/g, '');
    let out = '';
    for (let i = 0; i < text.length; i += 4) {
      const n = (chars.indexOf(text[i]) << 18) | (chars.indexOf(text[i + 1]) << 12) | ((chars.indexOf(text[i + 2]) & 63) << 6) | (chars.indexOf(text[i + 3]) & 63);
      out += String.fromCharCode((n >> 16) & 255);
      if (text[i + 2] !== undefined && text[i + 2] !== '=') out += String.fromCharCode((n >> 8) & 255);
      if (text[i + 3] !== undefined && text[i + 3] !== '=') out += String.fromCharCode(n & 255);
    }
    return out;
  };

  // Text.
  const bytesOf = (input) => input instanceof Uint8Array ? input : input instanceof ArrayBuffer ? new Uint8Array(input)
    : ArrayBuffer.isView(input) ? new Uint8Array(input.buffer, input.byteOffset, input.byteLength) : new Uint8Array(0);
  globalThis.TextDecoder = class TextDecoder {
    constructor(label) { this.encoding = (label || 'utf-8').toLowerCase(); }
    decode(input) { return input === undefined ? '' : native.decode(bytesOf(input), this.encoding); }
  };
  globalThis.TextEncoder = class TextEncoder {
    get encoding() { return 'utf-8'; }
    encode(text) {
      const utf8 = unescape(encodeURIComponent(String(text ?? '')));
      const out = new Uint8Array(utf8.length);
      for (let i = 0; i < utf8.length; i++) out[i] = utf8.charCodeAt(i);
      return out;
    }
  };

  // Headers, Request, Response, FormData, and fetch.
  class Headers {
    constructor(init) {
      this.map = new Map();
      if (init instanceof Headers) init.forEach((v, k) => this.set(k, v));
      else if (Array.isArray(init)) init.forEach(([k, v]) => this.append(k, v));
      else if (init) Object.keys(init).forEach((k) => { if (init[k] !== undefined) this.set(k, init[k]); });
    }
    append(k, v) { const key = String(k).toLowerCase(); this.map.set(key, this.map.has(key) ? this.map.get(key) + ', ' + v : String(v)); }
    set(k, v) { this.map.set(String(k).toLowerCase(), String(v)); }
    get(k) { const v = this.map.get(String(k).toLowerCase()); return v === undefined ? null : v; }
    has(k) { return this.map.has(String(k).toLowerCase()); }
    delete(k) { this.map.delete(String(k).toLowerCase()); }
    forEach(fn) { this.map.forEach((v, k) => fn(v, k, this)); }
    entries() { return this.map.entries(); }
    keys() { return this.map.keys(); }
    values() { return this.map.values(); }
    [Symbol.iterator]() { return this.map.entries(); }
    toObject() { const o = {}; this.map.forEach((v, k) => { o[k] = v; }); return o; }
  }
  globalThis.Headers = Headers;

  class FormData {
    constructor() { this.parts = []; }
    append(k, v) { this.parts.push([String(k), String(v)]); }
    set(k, v) { this.delete(k); this.append(k, v); }
    delete(k) { this.parts = this.parts.filter(([n]) => n !== k); }
    get(k) { const p = this.parts.find(([n]) => n === k); return p ? p[1] : null; }
    has(k) { return this.parts.some(([n]) => n === k); }
    entries() { return this.parts[Symbol.iterator](); }
    [Symbol.iterator]() { return this.parts[Symbol.iterator](); }
  }
  globalThis.FormData = FormData;

  class Response {
    constructor(body, init = {}) {
      this.bytes = body instanceof ArrayBuffer ? new Uint8Array(body) : typeof body === 'string' ? new TextEncoder().encode(body) : bytesOf(body || new Uint8Array(0));
      this.status = init.status ?? 200;
      this.statusText = init.statusText ?? '';
      this.headers = new Headers(init.headers);
      this.url = init.url ?? '';
      this.ok = this.status >= 200 && this.status < 300;
      this.redirected = false;
      this.bodyUsed = false;
    }
    async arrayBuffer() { return this.bytes.buffer.slice(this.bytes.byteOffset, this.bytes.byteOffset + this.bytes.byteLength); }
    async text() {
      const type = this.headers.get('content-type') || '';
      const charset = (/charset=([^;]+)/i.exec(type) || [])[1];
      return native.decode(this.bytes, (charset || 'utf-8').trim().toLowerCase());
    }
    async json() { return JSON.parse(await this.text()); }
    async blob() { return { size: this.bytes.byteLength, type: this.headers.get('content-type') || '', arrayBuffer: () => this.arrayBuffer() }; }
    clone() { return new Response(this.bytes.slice(), { status: this.status, statusText: this.statusText, headers: this.headers, url: this.url }); }
  }
  globalThis.Response = Response;

  class Request {
    constructor(input, init = {}) {
      this.url = typeof input === 'string' ? input : input instanceof URL ? input.toString() : input.url;
      this.method = (init.method || input.method || 'GET').toUpperCase();
      this.headers = new Headers(init.headers || input.headers);
      this.body = init.body ?? input.body;
    }
  }
  globalThis.Request = Request;

  globalThis.AbortController = globalThis.AbortController || class AbortController {
    constructor() { this.signal = { aborted: false, addEventListener() {}, removeEventListener() {} }; }
    abort() { this.signal.aborted = true; }
  };

  const pending = new Map();
  let nextRequest = 1;
  const encodeBody = (body, headers) => {
    if (body === undefined || body === null) return null;
    if (typeof body === 'string') return new TextEncoder().encode(body);
    if (body instanceof URLSearchParams) {
      if (!headers.has('content-type')) headers.set('content-type', 'application/x-www-form-urlencoded;charset=UTF-8');
      return new TextEncoder().encode(body.toString());
    }
    if (body instanceof FormData) {
      const boundary = '----AsabunkoForm' + Math.random().toString(16).slice(2);
      headers.set('content-type', 'multipart/form-data; boundary=' + boundary);
      let text = '';
      for (const [k, v] of body) text += '--' + boundary + '\r\nContent-Disposition: form-data; name="' + k + '"\r\n\r\n' + v + '\r\n';
      return new TextEncoder().encode(text + '--' + boundary + '--\r\n');
    }
    return bytesOf(body);
  };
  globalThis.fetch = function (input, init = {}) {
    const request = new Request(input, init);
    const body = encodeBody(request.body, request.headers);
    return new Promise((resolve, reject) => {
      const id = nextRequest++;
      pending.set(id, { resolve, reject });
      native.fetch(id, request.url, request.method, request.headers.toObject(), body);
    });
  };
  globalThis.__fetchDone = function (id, error, status, url, headers, body, cookies) {
    const p = pending.get(id);
    pending.delete(id);
    if (!p) return;
    if (error) { p.reject(new TypeError(error)); return; }
    const response = new Response(body, { status, url, headers });
    response.setCookies = cookies || [];
    p.resolve(response);
  };

  // Runs a function that can give a promise, and gives its result as JSON.
  globalThis.__invoke = async function (fn, ...args) {
    const value = await fn(...args);
    return JSON.stringify(value === undefined ? null : value);
  };
})();
