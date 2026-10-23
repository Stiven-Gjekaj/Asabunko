// Loads one LNReader plugin with the modules that the LNReader app gives to it.
// See src/plugins/pluginManager.ts of LNReader, under the MIT License.
(function () {
  'use strict';
  const lib = globalThis.__libraries;

  class Storage {
    constructor() { this.db = {}; }
    set(key, value, expires) { this.db[key] = { created: new Date(), value, expires: expires instanceof Date ? expires.getTime() : expires }; }
    get(key, raw) {
      const item = this.db[key];
      if (item && item.expires && Date.now() > item.expires) { delete this.db[key]; return undefined; }
      return raw ? item : item && item.value;
    }
    getAllKeys() { return Object.keys(this.db); }
    delete(key) { delete this.db[key]; }
    clearAll() { this.db = {}; }
  }
  const webStorage = { get: () => ({}) };

  const defaultHeaders = { 'Accept': '*/*', 'Accept-Language': '*', 'Sec-Fetch-Mode': 'cors' };
  const withDefaults = (init) => {
    init = init || {};
    if (init.headers instanceof Headers) {
      for (const [k, v] of Object.entries(defaultHeaders)) if (!init.headers.has(k)) init.headers.set(k, v);
    } else {
      init.headers = Object.assign({}, defaultHeaders, init.headers || {});
    }
    return init;
  };
  const fetchApi = (url, init) => fetch(url, withDefaults(init));
  const fetchText = async (url, init, encoding) => {
    try {
      const res = await fetch(url, withDefaults(init));
      if (!res.ok) return '';
      return new TextDecoder(encoding).decode(await res.arrayBuffer());
    } catch (e) { return ''; }
  };
  const fetchFile = async (url, init) => {
    try {
      const res = await fetch(url, withDefaults(init));
      if (!res.ok) return '';
      const bytes = new Uint8Array(await res.arrayBuffer());
      let text = '';
      for (let i = 0; i < bytes.length; i++) text += String.fromCharCode(bytes[i]);
      return btoa(text);
    } catch (e) { return ''; }
  };
  // A gRPC-web call, as fetchProto of LNReader: the request goes in a frame of 5 bytes and the
  // protobuf message, and the answer comes back in the same kind of frame.
  const fetchProto = async (protoInit, url, init) => {
    const root = lib.protobuf.parse(protoInit.proto).root;
    const Request = root.lookupType(protoInit.requestType);
    const problem = Request.verify(protoInit.requestData);
    if (problem) throw new Error('Invalid proto request: ' + problem);
    const body = Request.encode(Request.create(protoInit.requestData)).finish();
    const frame = new Uint8Array(5 + body.length);
    frame[1] = (body.length >>> 24) & 0xff; frame[2] = (body.length >>> 16) & 0xff;
    frame[3] = (body.length >>> 8) & 0xff; frame[4] = body.length & 0xff;
    frame.set(body, 5);
    const res = await fetch(url, withDefaults({ method: 'POST', ...(init || {}), body: frame }));
    const payload = new Uint8Array(await res.arrayBuffer());
    if (payload.length < 5) throw new Error('The proto answer is empty.');
    const length = ((payload[1] << 24) | (payload[2] << 16) | (payload[3] << 8) | payload[4]) >>> 0;
    const Response = root.lookupType(protoInit.responseType);
    return Response.toObject(Response.decode(payload.slice(5, 5 + length)), { longs: String, enums: String, bytes: String });
  };

  const isUrlAbsolute = (url) => {
    if (!url) return false;
    if (url.indexOf('//') === 0) return true;
    if (url.indexOf('://') === -1 || url.indexOf('.') === -1 || url.indexOf('/') === -1) return false;
    if (url.indexOf(':') > url.indexOf('/')) return false;
    return url.indexOf('://') < url.indexOf('.');
  };

  const NovelStatus = { Unknown: 'Unknown', Ongoing: 'Ongoing', Completed: 'Completed', Licensed: 'Licensed',
    PublishingFinished: 'Publishing Finished', Cancelled: 'Cancelled', OnHiatus: 'On Hiatus', STUB: 'STUB', Inactive: 'Inactive' };
  const FilterTypes = { TextInput: 'Text', Picker: 'Picker', CheckboxGroup: 'Checkbox', Switch: 'Switch', ExcludableCheckboxGroup: 'XCheckbox' };
  const defaultCover = 'https://github.com/LNReader/lnreader-plugins/blob/main/icons/src/coverNotAvailable.jpg?raw=true';

  // The settings of the plugin live here. The app writes the saved values before it loads the plugin.
  globalThis.__storage = new Storage();

  globalThis.__loadPlugin = function (code) {
    const packages = {
      'cheerio': lib.cheerio,
      'htmlparser2': lib.htmlparser2,
      'dayjs': lib.dayjs,
      'urlencode': { encode: (s) => encodeURIComponent(s), decode: (s) => decodeURIComponent(s) },
      '@libs/novelStatus': { NovelStatus },
      '@libs/fetch': { fetchApi, fetchText, fetchProto, fetchFile },
      '@libs/isAbsoluteUrl': { isUrlAbsolute },
      '@libs/filterInputs': { FilterTypes },
      '@libs/defaultCover': { defaultCover },
      // Some plugins take the default cover from the constants of the LNReader app.
      '@/types/constants': { defaultCover },
      '@libs/aes': lib.aes,
      '@libs/utils': lib.utils,
      '@libs/storage': { storage: globalThis.__storage, localStorage: webStorage, sessionStorage: webStorage },
    };
    const require = (name) => {
      if (!(name in packages)) throw new Error('The plugin asks for ' + name + ', which Asabunko does not have.');
      return packages[name];
    };
    const plugin = Function('require', 'module', 'const exports = module.exports = {};\n' + code + '\n;return exports.default')(require, {});
    if (!plugin || typeof plugin.popularNovels !== 'function') throw new Error('The file is not an LNReader plugin.');
    globalThis.plugin = plugin;
    const headers = (plugin.imageRequestInit && plugin.imageRequestInit.headers) || {};
    return { id: plugin.id, name: plugin.name, site: plugin.site, version: plugin.version, paged: typeof plugin.parsePage === 'function', imageHeaders: headers };
  };

  // The first value of each filter, as the LNReader app gives them.
  globalThis.__filters = function () {
    const filters = (globalThis.plugin && globalThis.plugin.filters) || {};
    const values = {};
    for (const key of Object.keys(filters)) values[key] = { type: filters[key].type, value: filters[key].value };
    return values;
  };

  const choices = (options) => (options || []).map((o) => ({ label: String(o.label), value: String(o.value) }));

  // The filters of the plugin, for the filter screen of the app.
  globalThis.__filterSpec = function () {
    const filters = (globalThis.plugin && globalThis.plugin.filters) || {};
    return Object.keys(filters).map((key) => ({ key, label: filters[key].label || key, type: filters[key].type,
      value: filters[key].value, options: choices(filters[key].options) }));
  };

  // The list of the plugin with the values of the user in place of the first values.
  globalThis.__browse = function (page, json) {
    const values = JSON.parse(json);
    const filters = __filters();
    for (const key of Object.keys(values)) if (filters[key]) filters[key].value = values[key];
    return globalThis.plugin.popularNovels(page, { showLatestNovels: false, filters });
  };

  // The settings of the plugin, with their values in the storage.
  globalThis.__settingSpec = function () {
    const settings = (globalThis.plugin && globalThis.plugin.pluginSettings) || {};
    return Object.keys(settings).map((key) => {
      const saved = globalThis.__storage.get(key);
      return { key, label: settings[key].label || key, type: settings[key].type || 'Text',
        value: saved === undefined ? settings[key].value : saved, options: choices(settings[key].options) };
    });
  };

  // A path of the site as a full URL.
  globalThis.__resolve = function (path, isNovel) {
    const plugin = globalThis.plugin;
    if (plugin.resolveUrl) return plugin.resolveUrl(path, isNovel);
    if (isUrlAbsolute(path)) return path;
    return new URL(path, plugin.site).href;
  };
})();
