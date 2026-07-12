/* =========================================================
   就活図鑑 サービスワーカー
   役割：①スマホに「アプリとしてインストール」できるようにする
        ②一度ひらいたページ・画像を保存し、電波が無くても起動できるようにする
   方針：index.html と data.js は「まずネットの最新版」を取りに行く
        （社員が data.js を更新したら、次にひらいた時すぐ反映される）
        画像・フォントなどは「まず手元の保存版」を使う（高速化）
   注意：データを更新しても sw.js の変更は不要。
        キャッシュの持ち方自体を変えた時だけ VERSION を上げる。
   ========================================================= */
const VERSION = 'shukatsu-zukan-v3'; /* v3: 「就活図鑑」へ改名＋アプリアイコン差し替え（画像を差し替えたらこの版数を上げる） */
const CORE = [
  './',
  './index.html',
  './data.js',
  './manifest.webmanifest',
  './assets/icons/app_icon_192.png',
  './assets/icons/app_icon_512.png',
  './assets/icons/app_icon.png',
  './assets/hero_dictionary.png'
];

self.addEventListener('install', (e) => {
  e.waitUntil(
    caches.open(VERSION).then((c) => c.addAll(CORE)).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== VERSION).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;

  const url = new URL(req.url);
  const isCore = req.mode === 'navigate'
    || url.pathname.endsWith('/data.js')
    || url.pathname.endsWith('/index.html');

  if (isCore) {
    // 最新優先：ネット→ダメなら保存版（オフライン起動）
    e.respondWith(
      fetch(req)
        .then((res) => {
          const copy = res.clone();
          caches.open(VERSION).then((c) => c.put(req, copy));
          return res;
        })
        .catch(() => caches.match(req, { ignoreSearch: true }).then((r) => r || caches.match('./index.html')))
    );
  } else {
    // 保存版優先：無ければネットから取って保存（ロゴ・フォント等）
    e.respondWith(
      caches.match(req).then((hit) => {
        if (hit) return hit;
        return fetch(req).then((res) => {
          if (res.ok || res.type === 'opaque') {
            const copy = res.clone();
            caches.open(VERSION).then((c) => c.put(req, copy));
          }
          return res;
        });
      })
    );
  }
});
