import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const source = fs.readFileSync('ios/AniCrN/StreamCapture.swift', 'utf8');
const script = source.match(/static let script = #"""\r?\n([\s\S]*?)\r?\n\s*"""#/)[1];
const messages = [];
class XHR { open() {} addEventListener() {} }
const window = { frames: [], addEventListener() {}, webkit: { messageHandlers: { anicrnStream: { postMessage: m => messages.push(m) } } }, fetch: async () => ({ url: 'https://cdn.test/play?id=1', headers: { get: () => 'application/vnd.apple.mpegurl' } }) };
vm.runInNewContext(script, { window, XMLHttpRequest: XHR, URL, location: { href: 'https://source.test/' }, navigator: { userAgent: 'FixtureUA' }, document: { addEventListener() {}, querySelectorAll: () => [] }, PerformanceObserver: class { observe() {} } });
await window.fetch('https://cdn.test/play?id=1');
await window.fetch('https://cdn.test/play?id=1');
assert.equal(messages.length, 1);
assert.equal(messages[0].type, 'hls');
assert.equal(messages[0].userAgent, 'FixtureUA');
assert.equal(messages[0].url, 'https://cdn.test/play?id=1');
console.log('Stream capture MIME/deduplication fixture passed');
