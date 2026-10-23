// erstapp.com: the website's files, and /download, which always serves the newest Erst.dmg from the
// erst-releases bucket that scripts/release.sh fills on every release.
const ARCHIVE = 'Erst.dmg';

async function download(request, env) {
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    return new Response('Method not allowed', { status: 405, headers: { allow: 'GET, HEAD' } });
  }
  const object = request.method === 'HEAD'
    ? await env.RELEASES.head(ARCHIVE)
    : await env.RELEASES.get(ARCHIVE, { range: request.headers, onlyIf: request.headers });
  if (!object) return new Response('Erst cannot be downloaded right now. Please try again soon.', { status: 503 });

  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set('content-type', 'application/x-apple-diskimage');
  headers.set('content-disposition', `attachment; filename="${ARCHIVE}"`);
  headers.set('etag', object.httpEtag);
  headers.set('accept-ranges', 'bytes');
  // A new release reaches every visitor within five minutes.
  headers.set('cache-control', 'public, max-age=300');
  if (request.method === 'HEAD') {
    headers.set('content-length', String(object.size));
    return new Response(null, { headers });
  }
  // A failed precondition, such as an If-None-Match that still matches, returns no body.
  if (!('body' in object)) return new Response(null, { status: 304, headers });
  if (object.range && request.headers.has('range')) {
    const { offset = 0, length = object.size - offset } = object.range;
    headers.set('content-range', `bytes ${offset}-${offset + length - 1}/${object.size}`);
    return new Response(object.body, { status: 206, headers });
  }
  return new Response(object.body, { headers });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.hostname === 'www.erstapp.com') {
      url.hostname = 'erstapp.com';
      return Response.redirect(url.toString(), 301);
    }
    if (url.pathname === '/download' || url.pathname === '/download/') return download(request, env);

    const response = await env.ASSETS.fetch(request);
    const headers = new Headers(response.headers);
    headers.set('strict-transport-security', 'max-age=31536000');
    headers.set('x-content-type-options', 'nosniff');
    headers.set('referrer-policy', 'strict-origin-when-cross-origin');
    headers.set('permissions-policy', 'camera=(), microphone=(), geolocation=()');
    // Pages are checked on every visit; art and fonts are kept an hour and refreshed in the background.
    if (url.pathname.startsWith('/assets/') || url.pathname.startsWith('/fonts/')) {
      headers.set('cache-control', 'public, max-age=3600, stale-while-revalidate=86400');
    }
    return new Response(response.body, { status: response.status, statusText: response.statusText, headers });
  },
};
