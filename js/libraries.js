// The libraries that the JavaScript sources of Asabunko ask for with require().
// scripts/build-js.sh bundles this file into AsaCore/Sources/AsaCore/Resources/libraries.js.
import 'core-js/actual/url';
import 'core-js/actual/url-search-params';
import 'core-js/actual/structured-clone';
import { load } from 'cheerio/slim';
import { Parser } from 'htmlparser2';
import dayjs from 'dayjs';
import { gcm } from '@noble/ciphers/aes';
import { utf8ToBytes, bytesToUtf8 } from '@noble/ciphers/utils';
import { parse } from 'protobufjs';

globalThis.__libraries = {
  cheerio: { load },
  htmlparser2: { Parser },
  dayjs,
  aes: { gcm },
  utils: { utf8ToBytes, bytesToUtf8 },
  protobuf: { parse },
};
