// The echoes behind the page, drawn the way brand/tools/readme_art.py develops the brand art: heat
// that cools with distance, a little grain, and the icon's thermal palette. One echo runs the
// whole page: it travels slowly outward on its own, and scrolling pushes it further.
(() => {
  const canvas = document.querySelector('.echo');
  if (!canvas) return;
  const gl = canvas.getContext('webgl', { antialias: false, alpha: false, premultipliedAlpha: false });
  if (!gl) return;

  const MAX_FIELDS = 3;
  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)');

  const vertex = `
    attribute vec2 a_position;
    void main() { gl_Position = vec4(a_position, 0.0, 1.0); }
  `;

  const fragment = `
    precision highp float;
    uniform vec2 u_resolution;
    uniform int u_count;
    uniform vec4 u_rect[${MAX_FIELDS}];
    uniform vec4 u_source[${MAX_FIELDS}];
    uniform vec4 u_motion[${MAX_FIELDS}];
    uniform vec4 u_words[${MAX_FIELDS}];
    uniform vec4 u_words2[${MAX_FIELDS}];

    const float GRAIN = 0.12;

    // HeatPalette: the ground, then the ramp to butter.
    vec3 palette(float h) {
      vec3 c0 = vec3(0.055, 0.055, 0.059);
      vec3 c1 = vec3(0.165, 0.090, 0.082);
      vec3 c2 = vec3(0.447, 0.255, 0.227);
      vec3 c3 = vec3(0.765, 0.396, 0.341);
      vec3 c4 = vec3(0.835, 0.455, 0.365);
      vec3 c5 = vec3(0.957, 0.635, 0.388);
      vec3 c6 = vec3(0.980, 0.765, 0.443);
      vec3 c7 = vec3(0.988, 0.824, 0.482);
      h = clamp(h, 0.0, 1.0);
      if (h < 0.18) return mix(c0, c1, h / 0.18);
      if (h < 0.34) return mix(c1, c2, (h - 0.18) / 0.16);
      if (h < 0.48) return mix(c2, c3, (h - 0.34) / 0.14);
      if (h < 0.60) return mix(c3, c4, (h - 0.48) / 0.12);
      if (h < 0.74) return mix(c4, c5, (h - 0.60) / 0.14);
      if (h < 0.88) return mix(c5, c6, (h - 0.74) / 0.14);
      return mix(c6, c7, (h - 0.88) / 0.12);
    }

    float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
    // A stroke of width w, softened by heat diffusion sigma, at distance x from its center line.
    float stroke(float x, float w, float sigma) {
      return 1.0 - smoothstep(w * 0.5 - sigma, w * 0.5 + sigma * 1.6, x);
    }

    float roundedRect(vec2 p, vec2 center, vec2 halfSize, float r) {
      vec2 q = abs(p - center) - (halfSize - vec2(r));
      return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
    }

    // How far p is from a box given as x, y, width, height; negative inside it.
    float boxDistance(vec2 p, vec4 b) {
      vec2 q = abs(p - (b.xy + b.zw * 0.5)) - b.zw * 0.5;
      return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
    }

    float smooth01(float a, float b, float x) {
      float k = clamp((x - a) / (b - a), 0.0, 1.0);
      return k * k * (3.0 - 2.0 * k);
    }

    // EchoFalloff: rings start at r0 and step outward; near ones are wide and hot, far ones thin
    // and cold. phase moves every ring outward, in rings; new rings rise from the source.
    float rings(float d, float r0, float step, float count, float width, float coldest, float sigma, float phase, float reach) {
      float t = (d - r0) / step - phase;
      float k = floor(t + 0.5);
      float radius = r0 + (k + phase) * step;
      float x = abs(d - radius);
      float spread = clamp((radius - r0) / (step * (count - 1.0)), 0.0, 1.0);
      float heat = 1.0 - (1.0 - coldest) * pow(spread, 0.8);
      float w = width * (1.6 - 0.9 * spread);
      float born = smoothstep(r0 - step * 0.6, r0 + step * 0.4, radius);
      float gone = 1.0 - smoothstep(r0 + step * (count - 1.0), r0 + step * (count + 0.4), radius);
      float shown = smoothstep(reach + step, reach - step, radius);
      return stroke(x, w, sigma) * heat * born * gone * shown;
    }

    void main() {
      vec2 p = vec2(gl_FragCoord.x, u_resolution.y - gl_FragCoord.y);
      float heat = 0.0;
      for (int i = 0; i < ${MAX_FIELDS}; i++) {
        if (i >= u_count) break;
        vec4 rect = u_rect[i];
        if (p.y < rect.y || p.y > rect.y + rect.w) continue;
        vec4 source = u_source[i];
        vec4 motion = u_motion[i];
        float kind = source.x;
        vec2 c = source.yz;
        float unit = source.w;
        if (kind < 1.5) {
          // The hero: echoes over a horizon, the mark at its center.
          float above = smoothstep(-2.0 * unit, 2.0 * unit, c.y - p.y);
          float ring = rings(distance(p, c), 64.0 * unit, 22.8 * unit, 10.0, 4.2 * unit, 0.12, 2.6 * unit, motion.x, motion.y) * above;
          float horizon = stroke(abs(p.y - c.y), 3.6 * unit, 2.6 * unit) * 0.5
            * smoothstep(motion.z + 60.0 * unit, motion.z - 60.0 * unit, abs(p.x - c.x))
            * clamp(motion.z / (40.0 * unit), 0.0, 1.0);
          heat = max(heat, max(ring, horizon) * 1.18);
        } else if (kind < 2.5) {
          // The ground: the film's echo seen from very close. Its source sits far outside the
          // window, so only the long arcs of two or three rings cross the page, and each section
          // sees them from another side. The rings cool with distance by getting thinner and
          // dimmer. Scrolling carries them outward with momentum; while the page moves they leave
          // hot, smear behind their own travel and come a little closer, and they sharpen as they
          // settle.
          float lambda = unit;
          float vel = motion.y;
          float energy = motion.w;
          vec2 view = u_resolution * 0.5;
          vec2 q = view + (p - view) / (1.0 + 0.1 * energy);
          float d = distance(q, c);
          float near = max(distance(c, view) - 0.5 * length(u_resolution), 0.0);
          float spread = clamp((d - near) / (0.8 * length(u_resolution)), 0.0, 1.0);
          float f = fract((d - motion.x) / lambda);
          float sigma = mix(0.13, 0.08, spread);
          float trail = sigma * (1.0 + 2.2 * abs(vel));
          float sInner = vel >= 0.0 ? sigma : trail;
          float sOuter = vel >= 0.0 ? trail : sigma;
          float crest = max(exp(-0.5 * f * f / (sInner * sInner)), exp(-0.5 * (1.0 - f) * (1.0 - f) / (sOuter * sOuter)));
          float cool = 1.0 - 0.65 * pow(spread, 0.8);
          float clear = mix(0.42, 1.0, smooth01(0.0, 0.2 * lambda, boxDistance(p, u_words[i])))
            * mix(0.42, 1.0, smooth01(0.0, 0.2 * lambda, boxDistance(p, u_words2[i])));
          heat = max(heat, (0.035 + (0.4 + 0.2 * energy) * crest) * cool * clear * motion.z);
        } else {
          // The Mac: echoes rise inside the screen and stop at its edge.
          vec2 halfSize = vec2(rect.z, rect.w) * 0.5;
          vec2 center = vec2(rect.x + halfSize.x, rect.y + halfSize.y);
          float inside = 1.0 - smoothstep(-0.5, 0.5, roundedRect(p, center, halfSize - vec2(7.0 * unit), 19.0 * unit));
          float above = smoothstep(-2.0 * unit, 2.0 * unit, c.y - p.y);
          float ring = rings(distance(p, c), 70.0 * unit, 50.0 * unit, 9.0, 6.0 * unit, 0.22, 5.2 * unit, motion.x, 1e6);
          heat = max(heat, ring * inside * above * 1.2);
        }
      }
      if (heat < 0.002) { gl_FragColor = vec4(palette(0.0), 1.0); return; }
      float grain = (GRAIN / 3.0) * (hash(p) + hash(p + 17.31) + hash(p + 41.7)) - GRAIN / 2.0;
      float k = 1.0 - clamp(heat / 0.1, 0.0, 1.0);
      float floorHeat = 0.025 * k * k * (3.0 - 2.0 * k);
      gl_FragColor = vec4(palette(heat + grain - floorHeat), 1.0);
    }
  `;

  function compile(type, source) {
    const shader = gl.createShader(type);
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(shader));
    return shader;
  }

  let program;
  try {
    program = gl.createProgram();
    gl.attachShader(program, compile(gl.VERTEX_SHADER, vertex));
    gl.attachShader(program, compile(gl.FRAGMENT_SHADER, fragment));
    gl.linkProgram(program);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(program));
  } catch (error) {
    console.warn('Erst: echoes fall back to stills: ' + (error && error.message));
    return;
  }
  gl.useProgram(program);
  const buffer = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);
  const position = gl.getAttribLocation(program, 'a_position');
  gl.enableVertexAttribArray(position);
  gl.vertexAttribPointer(position, 2, gl.FLOAT, false, 0, 0);
  const uniform = (name) => gl.getUniformLocation(program, name);
  const u = {
    resolution: uniform('u_resolution'), count: uniform('u_count'), rect: uniform('u_rect'), source: uniform('u_source'),
    motion: uniform('u_motion'), words: uniform('u_words'), words2: uniform('u_words2'),
  };
  document.documentElement.classList.add('gl');

  const q = (selector) => document.querySelector(selector);
  const hero = q('[data-echo="horizon"]');
  const mark = hero && hero.querySelector('.hero__mark');
  const macStage = q('[data-echo="mac"]');
  // Where the ground is seen from, in the order the page reaches them. The echo's source sits
  // outside the window, `reach` window heights from its middle at `angle` degrees (0 is to the
  // right, 90 below), on the side of the screen and away from the words. The ground glides to
  // whichever place is nearest the middle of the window, so its arcs turn and flatten from one
  // section to the next. It rises after the mark and fades at the Mac, whose own echoes take over.
  const anchors = [
    { el: mark, strength: 0, angle: 90, reach: 1.05 },
    { el: q('.chapter--timeline .shot'), strength: 1, angle: 90, reach: 1.05, words: q('.chapter--timeline .chapter__copy') },
    { el: q('.chapter--search .shot img'), strength: 1, angle: 20, reach: 1.25, words: q('.chapter--search .split__copy') },
    { el: q('.chapter--activity .shot img'), strength: 1, angle: 160, reach: 1.45, words: q('.chapter--activity .split__copy') },
    { el: q('.chapter--agents .terminals'), strength: 0.85, angle: 215, reach: 1.3, words: q('.chapter--agents .chapter__copy') },
    { el: macStage, strength: 0, angle: 240, reach: 1.3 },
  ].filter((anchor) => anchor.el);

  // The hero's echoes spread from the mark once it arrives, and the horizon draws out from it.
  let introStart = null;
  const INTRO_MS = 1600;
  let introDone = reduceMotion.matches;
  window.addEventListener('erst:arrived', () => { introStart = performance.now() + 120; request(); }, { once: true });

  let dpr = 1;
  function resize() {
    dpr = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = Math.round(window.innerWidth * dpr);
    canvas.height = Math.round(window.innerHeight * dpr);
    gl.viewport(0, 0, canvas.width, canvas.height);
  }

  function visible(r) { return r.bottom > -200 && r.top < window.innerHeight + 200; }
  const box = (r) => [r.left * dpr, r.top * dpr, r.width * dpr, r.height * dpr];
  const NO_WORDS = [-1e6, -1e6, 0, 0];
  // The lines of a chapter's words, as one box: its heading and lead.
  function wordsBox(root) {
    if (!root) return NO_WORDS;
    const rects = [...root.querySelectorAll('h2, p')].map((el) => el.getBoundingClientRect());
    if (!rects.length) return NO_WORDS;
    const left = Math.min(...rects.map((r) => r.left)), top = Math.min(...rects.map((r) => r.top));
    const right = Math.max(...rects.map((r) => r.right)), bottom = Math.max(...rects.map((r) => r.bottom));
    return [left * dpr, top * dpr, (right - left) * dpr, (bottom - top) * dpr];
  }

  // The ground's size follows the window: its rings are a little over half a window apart.
  const groundBase = () => Math.max(window.innerHeight, window.innerWidth * 0.55);

  // The scroll as the ground feels it: it follows the page with a little momentum, and its
  // velocity, signed and eased, says how hard and which way the rings are being pushed.
  let glide = window.scrollY, velocity = 0, lastNow = 0;
  function measureMotion(now) {
    const dt = lastNow ? Math.min(Math.max((now - lastNow) / 1000, 0.001), 0.1) : 0.016;
    lastNow = now;
    const before = glide;
    glide += (window.scrollY - glide) * (1 - Math.exp(-dt / 0.22));
    const target = Math.max(-1, Math.min(1, (glide - before) / dt / (2.2 * groundBase())));
    velocity += (target - velocity) * (1 - Math.exp(-dt / (Math.abs(target) > Math.abs(velocity) ? 0.08 : 0.5)));
  }

  function ground(phase) {
    const vw = window.innerWidth, vh = window.innerHeight;
    const base = groundBase();
    let total = 0, angle = 0, reach = 0, strength = 0;
    const near = [];
    for (const anchor of anchors) {
      const r = anchor.el.getBoundingClientRect();
      const weight = Math.exp(-(((r.top + r.height / 2 - vh / 2) / (0.55 * vh)) ** 2));
      if (weight < 1e-4) continue;
      total += weight;
      angle += weight * anchor.angle;
      reach += weight * anchor.reach;
      strength += weight * anchor.strength;
      if (anchor.words) near.push({ weight, words: anchor.words });
    }
    if (total < 1e-4) return null;
    near.sort((a, b) => b.weight - a.weight);
    const a = ((angle / total) * Math.PI) / 180;
    const d = (reach / total) * base;
    const lambda = 0.58 * base;
    return {
      source: [2, (vw / 2 + Math.cos(a) * d) * dpr, (vh / 2 + Math.sin(a) * d) * dpr, lambda * dpr],
      motion: [phase(lambda) * dpr, velocity, strength / Math.max(total, 0.25), Math.abs(velocity)],
      words: wordsBox(near[0] && near[0].words), words2: wordsBox(near[1] && near[1].words),
    };
  }

  // Returns true while something on screen travels on its own.
  function draw(now) {
    const still = reduceMotion.matches;
    const scroll = still ? 0 : window.scrollY;
    const time = still ? 0 : now / 1000;
    if (still) { glide = window.scrollY; velocity = 0; } else measureMotion(now);
    const fields = { rect: [], source: [], motion: [], words: [], words2: [] };
    const push = (rect, source, motion, words = NO_WORDS, words2 = NO_WORDS) => {
      fields.rect.push(...rect); fields.source.push(...source); fields.motion.push(...motion);
      fields.words.push(...words); fields.words2.push(...words2);
    };

    const g = ground((lambda) => (still ? 0 : time * 0.05 * lambda + glide * 0.5));
    if (g && g.motion[2] > 0.01) push([0, 0, canvas.width, canvas.height], g.source, g.motion, g.words, g.words2);

    if (hero && mark) {
      const h = hero.getBoundingClientRect();
      if (visible(h)) {
        const m = mark.getBoundingClientRect();
        // The mark image is 260 points wide at the art's 1440 point scale, where a unit is 2.4 points.
        const unit = (m.width / 260) * 2.4 * dpr;
        const cx = (m.left + m.width / 2) * dpr;
        const cy = (m.top + m.height / 2) * dpr;
        let reach = 1e6, line = 1e6;
        if (!introDone) {
          const t = introStart === null ? 0 : Math.min(Math.max((now - introStart) / INTRO_MS, 0), 1);
          const eased = 1 - Math.pow(1 - t, 3);
          reach = (40 + 22.8 * 11 * eased) * unit;
          line = eased * h.width * 0.6 * dpr;
          if (t >= 1) introDone = true;
        }
        push(box(h), [1, cx, cy, unit], [scroll / 90 + time * 0.3, reach, line, 0]);
      }
    }

    if (macStage) {
      const r = macStage.getBoundingClientRect();
      if (visible(r)) {
        // The frame image is the Mac at 0.9 of the README art: its screen is 756 by 472.5 points
        // of a 1440 by 640 stage, 40 points from the top.
        const k = r.width / 1440;
        const unit = 0.9 * k * dpr;
        const sw = 756 * k, sh = 472.5 * k;
        const sx = r.left + (r.width - sw) / 2, sy = r.top + 40 * k;
        push([sx * dpr, sy * dpr, sw * dpr, sh * dpr], [3, (sx + sw / 2) * dpr, (sy + sh - 8 * 0.9 * k) * dpr, unit], [scroll / 140 + time * 0.25, 0, 0, 0]);
      }
    }

    const count = Math.min(fields.rect.length / 4, MAX_FIELDS);
    for (const key in fields) {
      fields[key].length = Math.min(fields[key].length, MAX_FIELDS * 4);
      while (fields[key].length < MAX_FIELDS * 4) fields[key].push(0);
    }
    gl.uniform2f(u.resolution, canvas.width, canvas.height);
    gl.uniform1i(u.count, count);
    for (const key in fields) gl.uniform4fv(u[key], new Float32Array(fields[key]));
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
    return count > 0 && !still;
  }

  let pending = false;
  function request() {
    if (pending) return;
    pending = true;
    requestAnimationFrame((now) => {
      pending = false;
      if (draw(now) || !introDone) request();
    });
  }

  resize();
  request();
  window.addEventListener('scroll', request, { passive: true });
  window.addEventListener('resize', () => { resize(); request(); });
  reduceMotion.addEventListener('change', request);
  if (document.fonts) document.fonts.ready.then(request);
  window.addEventListener('load', request);
})();
