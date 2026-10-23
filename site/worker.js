// erstapp.com: the home page, plus what the erst-releases bucket holds, which
// scripts/release.sh fills on every release: /download serves the newest Erst.dmg,
// /download/v<version>/Erst.dmg each version's, and /appcast.xml the feed the app updates from.
const VERSIONED = /^\/download\/(v\d+\.\d+\.\d+)\/Erst\.dmg$/;

async function serve(request, env, key, type, headersFor) {
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    return new Response('Method not allowed', { status: 405, headers: { allow: 'GET, HEAD' } });
  }
  const object = request.method === 'HEAD'
    ? await env.RELEASES.head(key)
    : await env.RELEASES.get(key, { range: request.headers, onlyIf: request.headers });
  if (!object) return new Response('Not available right now. Please try again soon.', { status: 404 });

  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set('content-type', type);
  headers.set('etag', object.httpEtag);
  headers.set('accept-ranges', 'bytes');
  for (const [name, value] of Object.entries(headersFor)) headers.set(name, value);
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
    const archive = { 'content-disposition': 'attachment; filename="Erst.dmg"' };
    // A new release reaches every visitor and every installed copy within five minutes.
    if (url.pathname === '/download' || url.pathname === '/download/') {
      return serve(request, env, 'Erst.dmg', 'application/x-apple-diskimage', { ...archive, 'cache-control': 'public, max-age=300' });
    }
    const versioned = url.pathname.match(VERSIONED);
    if (versioned) {
      return serve(request, env, `${versioned[1]}/Erst.dmg`, 'application/x-apple-diskimage', { ...archive, 'cache-control': 'public, max-age=31536000, immutable' });
    }
    if (url.pathname === '/appcast.xml') {
      return serve(request, env, 'appcast.xml', 'application/xml; charset=utf-8', { 'cache-control': 'public, max-age=300' });
    }

    const response = await env.ASSETS.fetch(request);
    const headers = new Headers(response.headers);
    headers.set('strict-transport-security', 'max-age=31536000');
    headers.set('x-content-type-options', 'nosniff');
    headers.set('referrer-policy', 'strict-origin-when-cross-origin');
    headers.set('permissions-policy', 'camera=(), microphone=(), geolocation=()');
    headers.set('cross-origin-opener-policy', 'same-origin');
    // The one inline script in index.html is allowed by its hash; change it and the hash must change too.
    headers.set('content-security-policy', "default-src 'self'; script-src 'self' 'sha256-e2g5HkZP+fghbsY1m7moq4GopOo7zRRaAHNyQ2Q7oSI=' https://static.cloudflareinsights.com; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'self' https://api.github.com https://cloudflareinsights.com; object-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'; upgrade-insecure-requests");
    return new Response(response.body, { status: response.status, statusText: response.statusText, headers });
  },
};
