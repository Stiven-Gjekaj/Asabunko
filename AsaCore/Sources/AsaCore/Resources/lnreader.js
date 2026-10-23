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
  const fetchProto = async () => { throw new Error('This source needs protobuf, which Asabunko does not have.'); };

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
      '@libs/aes': lib.aes,
      '@libs/utils': lib.utils,
      '@libs/storage': { storage: new Storage(), localStorage: webStorage, sessionStorage: webStorage },
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

  // A path of the site as a full URL.
  globalThis.__resolve = function (path, isNovel) {
    const plugin = globalThis.plugin;
    if (plugin.resolveUrl) return plugin.resolveUrl(path, isNovel);
    if (isUrlAbsolute(path)) return path;
    return new URL(path, plugin.site).href;
  };
})();
