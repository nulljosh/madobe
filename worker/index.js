// Landing demo proxy: GET /go?u=<url> fetches a page and drops the headers that stop it being framed.
// ponytail: HTML only, GET only, iframe requests only, sandboxed frame, no cookies either way; no rewriting beyond <base> and link capture. Add rate limiting if abused.
const CAPTURE = `<script>addEventListener('click',e=>{const a=e.target.closest&&e.target.closest('a[href]');if(!a||e.defaultPrevented)return;e.preventDefault();parent.postMessage({madobe:a.href},'*')},true);addEventListener('submit',e=>{const f=e.target;if((f.method||'get').toLowerCase()!=='get')return;e.preventDefault();const u=new URL(f.action||location.href);new FormData(f).forEach((v,k)=>u.searchParams.set(k,v));parent.postMessage({madobe:u.href},'*')},true)</script>`;

const PRIVATE = /^(localhost|.*\.local|.*\.internal|\[.*\]|\d+\.\d+\.\d+\.\d+)$/i;

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    if (url.pathname !== '/go') return env.ASSETS.fetch(req);
    if (req.method !== 'GET' || req.headers.get('Sec-Fetch-Dest') !== 'iframe') return new Response('iframe only', { status: 403 });
    let target;
    try { target = new URL(url.searchParams.get('u')); } catch { return new Response('bad url', { status: 400 }); }
    if (!/^https?:$/.test(target.protocol) || PRIVATE.test(target.hostname)) return new Response('bad url', { status: 400 });
    let r;
    try {
      r = await fetch(target, { redirect: 'follow', headers: { 'User-Agent': 'Mozilla/5.0 (Macintosh) AppleWebKit/605.1.15 Safari/605.1.15', Accept: 'text/html' } });
    } catch { return new Response('could not load ' + target.host, { status: 502 }); }
    if (!(r.headers.get('content-type') || '').includes('text/html')) return new Response('not a page', { status: 415 });
    const html = (await r.text()).replace(/<head[^>]*>/i, m => `${m}<base href="${r.url}">${CAPTURE}`);
    return new Response(html, { headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' } });
  },
};
