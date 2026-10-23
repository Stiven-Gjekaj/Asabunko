// The Application global of the Paperback 0.9 extensions, and the calls of the host.
// It follows the types and the runtime polyfills of the Paperback toolchain, under the MIT License,
// with the fixes of the host: each interceptor gets the request of the one before it.
(function () {
  'use strict';
  const native = globalThis.__native;

  // Selectors: a string ID for a method of an object, so that the host keeps IDs and not functions.
  const registry = new Map();
  let nextSelector = 0;
  const SelectorRegistry = {
    registerSelector(id, object, key) { registry.set(id, { object, key }); },
    unregisterSelector(id) { registry.delete(id); },
    selector(id) {
      if (typeof id === 'function') return id;
      const entry = registry.get(id);
      if (!entry) return undefined;
      const value = entry.object[entry.key];
      return typeof value === 'function' ? value.bind(entry.object) : value;
    },
  };
  function Selector(object, key) {
    const tag = '$__selector_' + String(key);
    let id = object[tag];
    if (!id) {
      id = 'selector-' + (++nextSelector);
      Object.defineProperty(object, tag, { value: id, enumerable: false, configurable: true });
    }
    SelectorRegistry.registerSelector(id, object, key);
    return id;
  }

  // State: JSON with a tag for each Date, because the cookie store of the extensions keeps dates.
  const replace = function (key, value) {
    const raw = this[key];
    return raw instanceof Date ? { $date: raw.getTime() } : value;
  };
  const revive = (key, value) => (value && typeof value === 'object' && typeof value.$date === 'number' && Object.keys(value).length === 1) ? new Date(value.$date) : value;
  const save = (value) => value === undefined ? null : JSON.stringify(value, replace);
  const load = (text) => (text === null || text === undefined) ? undefined : JSON.parse(text, revive);

  // Requests, through the interceptors of the extension.
  const interceptors = [];
  const toBytes = (body) => {
    if (body === undefined || body === null) return undefined;
    if (typeof body === 'string' || body instanceof ArrayBuffer || ArrayBuffer.isView(body)) return body;
    const form = new FormData();
    for (const key of Object.keys(body)) if (body[key] !== undefined && body[key] !== null) form.append(key, String(body[key]));
    return form;
  };
  async function intercept(request) {
    let current = Object.assign({ method: 'GET' }, request);
    for (const item of interceptors.slice()) {
      const next = await SelectorRegistry.selector(item.request)(current);
      if (next) current = next;
    }
    return current;
  }
  function headersOf(request) {
    const headers = {};
    for (const key of Object.keys(request.headers || {})) {
      if (request.headers[key] !== undefined && request.headers[key] !== null) headers[key.toLowerCase()] = String(request.headers[key]);
    }
    if (request.cookies && Object.keys(request.cookies).length > 0) {
      const jar = {};
      for (const part of (headers['cookie'] || '').split(';')) {
        const index = part.indexOf('=');
        if (index > 0) jar[part.slice(0, index).trim()] = part.slice(index + 1).trim();
      }
      Object.assign(jar, request.cookies);
      headers['cookie'] = Object.keys(jar).map((k) => k + '=' + jar[k]).join('; ');
    }
    return headers;
  }
  async function scheduleRequest(request) {
    const req = await intercept(request);
    const method = (req.method || 'GET').toUpperCase();
    const url = String(req.url).split('#')[0];
    const res = await fetch(url, { method, headers: headersOf(req), body: (method === 'GET' || method === 'HEAD') ? undefined : toBytes(req.body) });
    const headers = res.headers.toObject();
    const response = {
      url: res.url || url, status: res.status, headers,
      mimeType: (headers['content-type'] || '').split(';')[0].trim() || undefined,
      cookies: (res.setCookies || []).map((c) => ({ name: c.name, value: c.value, domain: c.domain, path: c.path || '/',
        created: new Date(), expires: c.expires === undefined ? undefined : new Date(c.expires) })),
    };
    let data = await res.arrayBuffer();
    for (let k = interceptors.length - 1; k >= 0; k--) {
      const next = await SelectorRegistry.selector(interceptors[k].response)(req, response, data);
      if (next !== undefined) data = next;
    }
    return [response, data];
  }

  const bufferOf = (value) => value instanceof ArrayBuffer ? value : ArrayBuffer.isView(value)
    ? value.buffer.slice(value.byteOffset, value.byteOffset + value.byteLength) : new TextEncoder().encode(String(value)).buffer;

  globalThis.Application = {
    isResourceLimited: false, filterAdultTitles: false, filterMatureTitles: false,
    Selector, SelectorRegistry,
    registerInterceptor(id, request, response) { this.unregisterInterceptor(id); interceptors.push({ id, request, response }); },
    unregisterInterceptor(id) { const k = interceptors.findIndex((i) => i.id === id); if (k >= 0) interceptors.splice(k, 1); },
    setRedirectHandler() {},
    scheduleRequest,
    getDefaultUserAgent: async () => native.userAgent(),
    sleep: (seconds) => new Promise((resolve) => setTimeout(resolve, Number(seconds) * 1000)),
    getState: (key) => load(native.stateGet(String(key), false)),
    setState: (value, key) => native.stateSet(String(key), save(value), false),
    getSecureState: (key) => load(native.stateGet(String(key), true)),
    setSecureState: (value, key) => native.stateSet(String(key), save(value), true),
    resetAllState: () => native.stateReset(),
    arrayBufferToUTF8String: (buffer) => new TextDecoder('utf-8').decode(buffer),
    arrayBufferToASCIIString: (buffer) => new TextDecoder('windows-1252').decode(buffer),
    arrayBufferToUTF16String: (buffer) => new TextDecoder('utf-16le').decode(buffer),
    base64Encode: (value) => native.base64Encode(new Uint8Array(bufferOf(value))),
    base64Decode: (value) => native.base64Decode(typeof value === 'string' ? value : new TextDecoder().decode(value)),
    crypto_md5Hash: (value) => native.digest('MD5', new Uint8Array(bufferOf(value)), true),
    decodeHTMLEntities: (text) => native.decodeEntities(String(text)),
    executeInWebView: async (context) => ({ result: null, storage: { cookies: (context.storage && context.storage.cookies) || [] } }),
    registerDiscoverSection() {}, unregisterDiscoverSection() {}, registeredDiscoverSections: () => [],
    invalidateDiscoverSections() {},
    formDidChange() {},
    console_log: (m) => console.log(...[].concat(m)), console_warn: (m) => console.warn(...[].concat(m)), console_error: (m) => console.error(...[].concat(m)),
  };

  // The parts of Web Crypto that the extensions use: digests, AES-CBC, and AES-GCM.
  const nameOf = (algorithm) => String(typeof algorithm === 'string' ? algorithm : algorithm.name).toUpperCase();
  globalThis.crypto = {
    getRandomValues(array) { const bytes = native.random(array.byteLength); new Uint8Array(array.buffer, array.byteOffset, array.byteLength).set(new Uint8Array(bytes)); return array; },
    randomUUID: () => native.uuid(),
    subtle: {
      async digest(algorithm, data) { return native.digest(nameOf(algorithm), new Uint8Array(bufferOf(data)), false); },
      async importKey(format, data, algorithm, extractable, usages) {
        if (format !== 'raw') throw new Error('Asabunko imports only raw keys.');
        return { type: 'secret', algorithm: { name: nameOf(algorithm) }, extractable, usages, _raw: bufferOf(data) };
      },
      async exportKey(format, key) { return key._raw; },
      async decrypt(algorithm, key, data) { return check(native.aes(nameOf(algorithm), false, new Uint8Array(key._raw), new Uint8Array(bufferOf(algorithm.iv)), new Uint8Array(bufferOf(data)), algorithm.additionalData ? new Uint8Array(bufferOf(algorithm.additionalData)) : null)); },
      async encrypt(algorithm, key, data) { return check(native.aes(nameOf(algorithm), true, new Uint8Array(key._raw), new Uint8Array(bufferOf(algorithm.iv)), new Uint8Array(bufferOf(data)), algorithm.additionalData ? new Uint8Array(bufferOf(algorithm.additionalData)) : null)); },
    },
  };
  function check(result) {
    if (result === null || result === undefined) throw new Error('The operation failed.');
    return result;
  }

  // The calls of the host. Each list keeps the metadata of each page, so that page n uses the metadata of page n - 1.
  const cursors = {};
  const series = {};
  const chapters = {};
  const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
  const item = (i) => ({ id: String(i.mangaId), title: String(i.title || ''), cover: i.imageUrl || null });

  async function paged(key, page, load) {
    const list = cursors[key] || (cursors[key] = { 1: undefined });
    if (!(page in list)) return { items: [], hasMore: false };
    const before = list[page];
    const result = await load(before);
    const more = result && result.metadata !== undefined && result.metadata !== null && (result.items || []).length > 0 && !same(result.metadata, before);
    if (more) list[page + 1] = result.metadata;
    return { items: (result && result.items) || [], hasMore: !!more };
  }

  // The settings forms. The host keeps the ID of each form, and each call gives the form again after the change.
  const forms = new Map();
  let nextForm = 0;
  function formId(form) {
    let id = form.__asabunko_form;
    if (!id || forms.get(id) !== form) {
      id = 'form-' + (++nextForm);
      Object.defineProperty(form, '__asabunko_form', { value: id, enumerable: false, configurable: true });
      form.__underlying_formId = id;
      forms.set(id, form);
    }
    return id;
  }
  const label = (value) => value === undefined || value === null || typeof value === 'object' ? null : String(value);
  // A label row of a list of choices has a symbol as its value: a check for a choice that is in, a cross for a choice that is out.
  function mark(value) {
    if (!value || typeof value !== 'object' || !value.symbol) return null;
    return /xmark|minus|nosign/.test(String(value.symbol)) ? 'excluded' : 'included';
  }
  function row(item) {
    const base = { id: String(item.id), type: String(item.type), title: String(item.title || ''), subtitle: item.subtitle ? String(item.subtitle) : null };
    switch (item.type) {
      case 'labelRow': return { ...base, value: label(item.value), mark: mark(item.value), selectable: item.onSelect != null };
      case 'inputRow': return { ...base, value: item.value === undefined || item.value === null ? '' : String(item.value) };
      case 'toggleRow': return { ...base, on: !!item.value };
      case 'navigationRow': return { ...base, value: label(item.value), form: item.form ? formId(item.form) : null };
      default: return { ...base, selectable: item.onSelect != null };
    }
  }
  async function renderForm(id) {
    const form = forms.get(id);
    if (!form) throw new Error('The form is not open.');
    if (!form.__asabunko_seen) {
      Object.defineProperty(form, '__asabunko_seen', { value: true, enumerable: false, configurable: true });
      if (typeof form.formWillAppear === 'function') await form.formWillAppear();
    }
    const rows = new Map();
    const sections = ((await form.getSections()) || []).filter((s) => s && !s.isHidden).map((s, k) => ({
      id: String(s.id === undefined ? k : s.id), header: s.header ? String(s.header) : null, footer: s.footer ? String(s.footer) : null,
      rows: (s.items || []).filter((i) => i && !i.isHidden).map((i) => { rows.set(String(i.id), i); return row(i); }),
    }));
    Object.defineProperty(form, '__asabunko_rows', { value: rows, enumerable: false, configurable: true });
    return { id, submit: !!form.requiresExplicitSubmission, sections };
  }

  globalThis.__paperback = {
    async start(id) {
      if (typeof source !== 'object' || !source || typeof source[id] !== 'object') throw new Error('The file is not a Paperback extension with the ID ' + id + '.');
      globalThis.extension = source[id];
      await extension.initialise();
      const sections = typeof extension.getDiscoverSections === 'function' ? await extension.getDiscoverSections() : [];
      globalThis.__sections = sections || [];
      return { sections: __sections.map((s) => ({ id: String(s.id), title: String(s.title || ''), type: Number(s.type) })) };
    },
    async section(id, page) {
      const section = __sections.find((s) => String(s.id) === id);
      if (!section) return { items: [], hasMore: false };
      const result = await paged('section:' + id, page, (metadata) => extension.getDiscoverSectionItems(section, metadata));
      return { items: result.items.filter((i) => i.mangaId !== undefined).map(item), hasMore: result.hasMore };
    },
    async search(title, page) {
      const result = await paged('search:' + title, page, (metadata) => extension.getSearchResults({ title }, metadata, undefined));
      return { items: result.items.map(item), hasMore: result.hasMore };
    },
    // The search filters of the extension, for the filter screen of the app.
    async filters() {
      if (typeof extension.getSearchFilters !== 'function') return [];
      const list = (await extension.getSearchFilters()) || [];
      return list.map((f) => ({ id: String(f.id), title: String(f.title || f.id), type: String(f.type), value: f.value === undefined ? null : f.value,
        allowExclusion: !!f.allowExclusion, placeholder: f.placeholder || null,
        options: (f.options || []).map((o) => ({ label: String(o.value), value: String(o.id) })) }));
    },
    // A search with the values of the filters: a text for an input, an option ID for a dropdown,
    // and a map of option IDs to "included" or "excluded" for a multiselect.
    async browse(title, json, page) {
      const values = JSON.parse(json);
      const filters = Object.keys(values).map((id) => ({ id, value: values[id] }));
      const result = await paged('browse:' + title + json, page, (metadata) => extension.getSearchResults({ title, filters }, metadata, undefined));
      return { items: result.items.map(item), hasMore: result.hasMore };
    },
    async details(mangaId) {
      const manga = await extension.getMangaDetails(mangaId);
      series[mangaId] = manga;
      const list = typeof extension.getChapters === 'function' ? await extension.getChapters(manga) : [];
      for (const chapter of list) chapters[String(chapter.chapterId)] = chapter;
      const info = manga.mangaInfo || {};
      const date = (d) => d instanceof Date && !isNaN(d.getTime()) ? d.toISOString().slice(0, 10) : (typeof d === 'string' ? d.slice(0, 10) : null);
      const tags = [].concat(...(info.tagGroups || []).map((g) => (g.tags || []).map((t) => String(t.title))));
      return {
        title: String(info.primaryTitle || mangaId), cover: info.thumbnailUrl || null, summary: info.synopsis || null,
        author: [info.author, info.artist].filter((x, i, a) => x && a.indexOf(x) === i).join(', ') || null,
        status: info.status || null, tags, novel: info.contentType === 'novel',
        chapters: list.map((c) => ({ id: String(c.chapterId), title: c.title || null, number: typeof c.chapNum === 'number' && !isNaN(c.chapNum) ? c.chapNum : null,
          volume: typeof c.volume === 'number' && !isNaN(c.volume) ? c.volume : null, group: c.version || null, date: date(c.publishDate), index: typeof c.sortingIndex === 'number' ? c.sortingIndex : null })),
      };
    },
    hasChapter: (id) => id in chapters,
    async pages(chapterId) {
      const details = await extension.getChapterDetails(chapters[chapterId]);
      if (details.type === 'html') return { html: String(details.html) };
      const requests = [];
      for (const url of details.pages || []) {
        const req = await intercept({ url: String(url), method: 'GET' });
        requests.push({ url: String(req.url).split('#')[0], headers: headersOf(req) });
      }
      return { pages: requests };
    },
    async imageHeaders(url) { return headersOf(await intercept({ url, method: 'GET' })); },
    hasForm: () => typeof extension.getSettingsForm === 'function',
    // The root settings form, made again each time that the user opens the settings.
    async settingsForm() {
      if (typeof extension.getSettingsForm !== 'function') return null;
      forms.clear();
      return renderForm(formId(await extension.getSettingsForm()));
    },
    form: (id) => renderForm(id),
    // An action of a row: a text for an input, a switch value for a toggle, and null for a tap.
    async formAction(id, rowId, json) {
      const form = forms.get(id);
      const item = form && form.__asabunko_rows && form.__asabunko_rows.get(rowId);
      if (!item) throw new Error('The row is not in the form.');
      const value = JSON.parse(json);
      const action = SelectorRegistry.selector(item.type === 'inputRow' || item.type === 'toggleRow' ? item.onValueChange : item.onSelect);
      if (typeof action === 'function') await (value === null ? action() : action(value));
      return renderForm(id);
    },
    async formSubmit(id) {
      const form = forms.get(id);
      if (form && typeof form.formDidSubmit === 'function') await form.formDidSubmit();
      return true;
    },
  };
})();
