import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const source = fs.readFileSync('ios/AniCrN/StreamCapture.swift', 'utf8');
const script = source.match(/static let script = #"""\r?\n([\s\S]*?)\r?\n\s*"""#/)[1];
const messages = [];
class XHR {
  open() {}
  addEventListener(name, callback) { this[name] = callback; }
  getResponseHeader() { return this.mime; }
}
const listeners = {};
let pauses = 0, framePauses = 0;
const window = { frames: [{ postMessage: message => { if (message.anicrnPause) framePauses++; } }], addEventListener: (name, callback) => { listeners[name] = callback; }, webkit: { messageHandlers: { anicrnStream: { postMessage: m => messages.push(m) } } }, fetch: async () => ({ url: 'https://cdn.test/play?id=1', headers: { get: () => 'application/vnd.apple.mpegurl' } }) };
vm.runInNewContext(script, { window, XMLHttpRequest: XHR, URL, location: { href: 'https://source.test/' }, navigator: { userAgent: 'FixtureUA' }, document: { addEventListener() {}, querySelectorAll: () => [{ pause() { pauses++; } }] }, PerformanceObserver: class { observe() {} } });
await window.fetch('https://cdn.test/play?id=1');
await window.fetch('https://cdn.test/play?id=1');
assert.equal(messages.length, 1);
assert.equal(messages[0].type, 'hls');
assert.equal(messages[0].userAgent, 'FixtureUA');
assert.equal(messages[0].url, 'https://cdn.test/play?id=1');
const xhr = new XHR();
xhr.open('GET', 'https://cdn.test/resource');
xhr.mime = 'video/mp4'; xhr.responseURL = 'https://cdn.test/resource'; xhr.load();
assert.equal(messages[1].type, 'mp4');
const direct = new XHR(); direct.open('GET', '/movie.mp4?sig=abc');
assert.equal(messages[2].url, 'https://source.test/movie.mp4?sig=abc');
const blob = new XHR(); blob.open('GET', 'blob:https://source.test/abc');
assert.equal(messages.length, 3);
listeners.message({ data: { anicrnPause: true } });
assert.equal(pauses, 1); assert.equal(framePauses, 1);
console.log('Stream capture fetch/XHR MIME, direct MP4, deduplication and pause fixtures passed');
