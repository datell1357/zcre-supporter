import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';

const bridge = readFileSync(new URL('../../Sources/ZCREBunny/Resources/ZCUTExportBridge.js', import.meta.url), 'utf8');

function fixture(hostname = 'zcut.ai') {
  const folders = new Map();
  const downloads = [];
  const timers = [];
  const root = {
    async *entries() {
      for (const entry of folders) yield entry;
    },
    async getDirectoryHandle(name) {
      if (folders.has(name)) return folders.get(name);
      const folder = {
        kind: 'directory',
        name,
        files: new Map(),
        async *entries() { for (const entry of this.files) yield entry; },
        async getFileHandle(filename) {
          if (filename === '.zcre-export-probe') return { createWritable() {} };
          return this.files.get(filename);
        },
        async removeEntry(filename) { this.files.delete(filename); },
      };
      folders.set(name, folder);
      return folder;
    },
    async removeEntry(name) { folders.delete(name); },
  };
  const context = {
    location: { protocol: 'https:', hostname },
    navigator: { storage: { getDirectory: async () => root } },
    crypto: { randomUUID: () => 'test-id' },
    URL: { createObjectURL: () => 'blob:movie', revokeObjectURL: () => {} },
    document: {
      body: { appendChild: () => {} },
      createElement: () => ({ click() { downloads.push({ href: this.href, name: this.download }); }, remove() {} }),
    },
    setInterval(fn) { timers.push(fn); return timers.length; },
    clearInterval(timer) { timers[timer - 1] = null; },
    setTimeout() {},
    Date,
  };
  context.window = context;
  runInNewContext(bridge, context);
  return { context, folders, downloads, timers };
}

test('ZCUT export uses origin storage and downloads the completed MP4 once', async () => {
  const { context, folders, downloads, timers } = fixture();
  const folder = await context.showDirectoryPicker({ mode: 'readwrite', id: 'zcut-export' });
  assert.equal(await folder.queryPermission({ mode: 'readwrite' }), 'granted');
  assert.equal(await folder.requestPermission({ mode: 'readwrite' }), 'granted');
  const storageFolder = [...folders.values()][0];
  storageFolder.files.set('edited.mp4', { kind: 'file', getFile: async () => ({ size: 5, lastModified: 100 }) });
  for (let i = 0; i < 3; i++) await timers[0]();
  assert.deepEqual(downloads, [{ href: 'blob:movie', name: 'edited.mp4' }]);
  assert.equal(folders.size, 1);
  const reconnected = await context.showDirectoryPicker({ mode: 'readwrite', id: 'zcut-export' });
  assert.equal(reconnected, folder);
  for (let i = 0; i < 3; i++) await timers[1]();
  assert.equal(downloads.length, 1, 'reconnecting must not download an old result again');
  storageFolder.files.set('next.mp4', { kind: 'file', getFile: async () => ({ size: 10, lastModified: 200 }) });
  for (let i = 0; i < 3; i++) await timers[1]();
  assert.deepEqual(downloads.map(item => item.name), ['edited.mp4', 'next.mp4']);
  await context.showDirectoryPicker({ mode: 'readwrite', id: 'zcut-export' });
  storageFolder.files.set('edited.mp4', { kind: 'file', getFile: async () => ({ size: 6, lastModified: 300 }) });
  for (let i = 0; i < 3; i++) await timers[2]();
  assert.deepEqual(downloads.map(item => item.name), ['edited.mp4', 'next.mp4', 'edited.mp4']);
});

test('other hosts do not receive the folder picker', () => {
  const { context } = fixture('www.zcre.co.kr');
  assert.equal(context.showDirectoryPicker, undefined);
});

test('unrelated directory requests are not silently redirected to the export folder', async () => {
  const { context, folders } = fixture();
  await assert.rejects(context.showDirectoryPicker({ mode: 'read' }), { name: 'NotSupportedError' });
  assert.equal(folders.size, 0);
});
