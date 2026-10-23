// Arrivals, the terminals' one playthrough, and the live star count. Every part of the page is
// already visible without this script; it only decides when things arrive.
(() => {
  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  // The hero arrives once the fonts are in, so the headline never swaps faces mid-arrival.
  let arrived = false;
  const arrive = () => {
    if (arrived) return;
    arrived = true;
    document.querySelectorAll('.arrive').forEach((el) => el.classList.add('is-in'));
    // The echoes start from the mark the moment it arrives.
    window.dispatchEvent(new Event('erst:arrived'));
  };
  (document.fonts ? document.fonts.ready : Promise.resolve()).then(() => requestAnimationFrame(arrive));
  setTimeout(arrive, 1200);

  const seen = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      entry.target.classList.add('is-in');
      seen.unobserve(entry.target);
      if (entry.target.matches('[data-terminals]')) play(entry.target);
    }
  }, { rootMargin: '0px 0px -18% 0px' });
  document.querySelectorAll('[data-reveal], [data-terminals], .ending').forEach((el) => seen.observe(el));

  // Both sessions play at once and quickly: each command is typed, then its answer appears.
  const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  async function type(el, perChar) {
    const text = el.dataset.type;
    el.textContent = '';
    for (const char of text) {
      el.textContent += char;
      await wait(perChar + Math.random() * perChar * 0.6);
    }
  }
  async function play(root) {
    const steps = (term) => [...term.querySelectorAll('[data-step]')];
    const [claude, shell] = root.querySelectorAll('.term');
    if (reduceMotion) {
      root.querySelectorAll('[data-step]').forEach((el) => el.classList.add('is-shown'));
      return;
    }
    const typed = root.querySelectorAll('[data-type]');
    typed.forEach((el) => { el.textContent = ''; });
    const ask = async () => {
      await wait(120);
      await type(typed[0], 16);
      const [call, answer] = steps(claude);
      call.classList.add('is-shown');
      await wait(220);
      answer.classList.add('is-shown');
    };
    const search = async () => {
      await wait(360);
      await type(typed[1], 9);
      steps(shell).forEach((el, i) => setTimeout(() => el.classList.add('is-shown'), 80 + i * 120));
    };
    await Promise.all([ask(), search()]);
  }

  // A pinned sequence: on a wide window the screen holds still while the page scrolls, and the
  // scroll plays real frames of the app, as scrolling the timeline does. One frame at a time is
  // drawn on a canvas over the still image, on the next animation frame, with no blending. On a
  // wide window the frames start downloading as soon as the page has loaded, a few at a time,
  // spread over the whole day first and then filling the gaps, and the ones nearest the reader
  // jump the queue. They are decoded off the main thread, mostly ahead in the direction of the
  // scroll, so the frame the scroll reaches is already there.
  // Without script or with reduced motion the still image stays.
  const wide = window.matchMedia('(min-width: 40rem)');
  function sequence(track) {
    const still = track.querySelector('img');
    const count = Number(track.dataset.frames);
    const canvas = document.createElement('canvas');
    canvas.className = 'sequence__canvas';
    canvas.setAttribute('aria-hidden', 'true');
    still.after(canvas);
    const context = canvas.getContext('2d');
    // A screen with one pixel per point gets frames at half the size, a third of the download.
    const pattern = window.devicePixelRatio > 1.25
      ? track.dataset.sequence
      : track.getAttribute('data-sequence-1x') || track.dataset.sequence;
    const url = (i) => pattern.replace('%', String(i).padStart(2, '0'));

    // A blob per frame: undefined until asked for, null while it downloads, false if it failed.
    const blobs = new Array(count);
    const bitmaps = new Map();
    const decoding = new Set();
    const ahead = 12, behind = 3, parallel = 6;
    let index = 0, direction = 1, drawn = -1, queued = false, size = [0, 0];

    // The canvas has as many pixels as it covers on screen, so frames stay sharp on a Retina
    // screen. Frames are scaled as they are drawn: scaling them while decoding stalls the GPU.
    const measure = () => {
      const ratio = Number(still.getAttribute('height')) / Number(still.getAttribute('width'));
      const width = Math.round((canvas.clientWidth || still.clientWidth) * Math.min(window.devicePixelRatio || 1, 2));
      if (!width || width === size[0]) return;
      size = [width, Math.round(width * ratio)];
      canvas.width = size[0];
      canvas.height = size[1];
      for (const bitmap of bitmaps.values()) bitmap.close();
      bitmaps.clear();
      drawn = -1;
    };

    const wanted = (i) => i >= 0 && i < count && (i - index) * direction <= ahead && (index - i) * direction <= behind;
    const decode = () => {
      for (const [i, bitmap] of bitmaps) if (!wanted(i)) { bitmap.close(); bitmaps.delete(i); }
      const order = [];
      for (let step = 0; step <= ahead; step++) order.push(index + direction * step);
      for (let step = 1; step <= behind; step++) order.push(index - direction * step);
      for (const i of order) {
        if (decoding.size >= parallel) break;
        if (!wanted(i) || !blobs[i] || bitmaps.has(i) || decoding.has(i)) continue;
        decoding.add(i);
        const [width] = size;
        createImageBitmap(blobs[i]).then((bitmap) => {
          decoding.delete(i);
          if (width === size[0] && wanted(i)) bitmaps.set(i, bitmap);
          else bitmap.close();
          request();
        }, () => { decoding.delete(i); });
      }
    };
    // A frame not decoded yet is stood in for by the nearest one that is, looking back along the
    // scroll first, so the screen never runs ahead of the reader.
    const paint = () => {
      queued = false;
      decode();
      let pick = -1;
      for (let step = 0; step < count && pick < 0; step++) {
        if (bitmaps.has(index - direction * step)) pick = index - direction * step;
        else if (bitmaps.has(index + direction * step)) pick = index + direction * step;
      }
      if (pick < 0 || pick === drawn) return;
      context.drawImage(bitmaps.get(pick), 0, 0, canvas.width, canvas.height);
      drawn = pick;
    };
    const request = () => {
      if (queued) return;
      queued = true;
      requestAnimationFrame(paint);
    };

    const spread = [];
    for (let stride = 2 ** Math.ceil(Math.log2(count)); stride >= 1; stride /= 2) {
      for (let i = 0; i < count; i += stride) if (!spread.includes(i)) spread.push(i);
    }
    let fetching = 0;
    const near = () => {
      const r = track.getBoundingClientRect();
      return r.bottom > -window.innerHeight && r.top < window.innerHeight * 2;
    };
    const fetchMore = () => {
      while (fetching < 6) {
        let next = -1;
        if (near()) {
          for (let step = 0; step < count && next < 0; step++) {
            for (const i of [index + direction * step, index - direction * step]) {
              if (next < 0 && i >= 0 && i < count && blobs[i] === undefined) next = i;
            }
          }
        }
        if (next < 0) next = spread.find((i) => blobs[i] === undefined) ?? -1;
        if (next < 0) return;
        const i = next;
        blobs[i] = null;
        fetching++;
        fetch(url(i))
          .then((response) => (response.ok ? response.blob() : false), () => false)
          .then((blob) => {
            blobs[i] = blob;
            fetching--;
            request();
            fetchMore();
          });
      }
    };

    const scrub = () => {
      const r = track.getBoundingClientRect();
      // Pinned, the track's extra height is the scroll; unpinned, the screen's way through the window.
      const progress = wide.matches
        ? -r.top / Math.max(r.height - window.innerHeight, 1)
        : (window.innerHeight * 0.9 - r.top) / Math.max(window.innerHeight * 0.7 + r.height, 1);
      const next = Math.round(Math.min(Math.max(progress, 0), 1) * (count - 1));
      if (next !== index) direction = next > index ? 1 : -1;
      index = next;
      request();
    };
    const layout = () => {
      track.classList.toggle('scrubs', wide.matches);
      measure();
      scrub();
    };
    wide.addEventListener('change', layout);
    window.addEventListener('resize', layout);
    window.addEventListener('scroll', scrub, { passive: true });
    layout();

    // A narrow window waits until the day is close, so a phone only downloads what it will show.
    const start = () => { measure(); fetchMore(); };
    if (wide.matches) {
      if (document.readyState === 'complete') start();
      else window.addEventListener('load', start, { once: true });
    } else {
      const close = new IntersectionObserver((entries) => {
        if (entries.some((entry) => entry.isIntersecting)) { start(); close.disconnect(); }
      }, { rootMargin: '100% 0px' });
      close.observe(track);
    }
  }
  if (!reduceMotion) document.querySelectorAll('[data-sequence]').forEach(sequence);

  // The search types its query and its results come in, once, when it comes into view: a second
  // and a half on its own, like the terminals. The pieces are cut from the finished screen, and an
  // empty panel sits under them, so when it ends the screen is exactly the still image beneath.
  const typing = document.querySelector('[data-typing]');
  if (typing && !reduceMotion) {
    // Rectangles in the 2x screen's pixels, and where each typed character of "open source" ends.
    const W = 1872, H = 1170;
    const query = { x: 100, y: 40, w: 262, h: 74, start: 116, ends: [138, 162, 187, 208, 214, 240, 264, 286, 306, 325, 352] };
    const results = [[44, 239, 566, 493], [651, 239, 535, 493], [1243, 239, 534, 493], [44, 789, 566, 336], [651, 789, 535, 336], [1243, 789, 534, 336]];
    const still = typing.querySelector('img');
    const overlay = document.createElement('div');
    overlay.className = 'typing';
    overlay.setAttribute('aria-hidden', 'true');
    const percent = (value, total) => (value / total) * 100 + '%';
    const piece = ([x, y, w, h], className) => {
      const el = document.createElement('span');
      el.className = className;
      Object.assign(el.style, { left: percent(x, W), top: percent(y, H), width: percent(w, W), height: percent(h, H) });
      const img = document.createElement('img');
      img.src = still.getAttribute('src');
      img.alt = '';
      Object.assign(img.style, { width: percent(W, w), left: percent(-x, w), top: percent(-y, h) });
      el.append(img);
      overlay.append(el);
      return el;
    };
    const text = piece([query.x, query.y, query.w, query.h], 'typing__piece');
    const cards = results.map((rect) => piece(rect, 'typing__piece typing__card'));
    const caret = document.createElement('span');
    caret.className = 'typing__caret is-waiting';
    Object.assign(caret.style, { top: percent(49, H), height: percent(48, H), width: percent(3, W) });
    overlay.append(caret);
    const reveal = (edge) => {
      text.style.clipPath = 'inset(0 ' + percent(query.x + query.w - edge, query.w) + ' 0 0)';
      caret.style.left = percent(edge - 1, W);
    };
    reveal(query.start);
    still.after(overlay);

    const play = async () => {
      // The panel finishes arriving first.
      await wait(600);
      caret.classList.remove('is-waiting');
      for (const edge of query.ends) {
        reveal(edge);
        await wait(46 + Math.random() * 28);
      }
      // The screen's own caret sits at the end of the query.
      caret.remove();
      await wait(120);
      cards.forEach((card, i) => setTimeout(() => card.classList.add('is-shown'), i * 70));
      await wait(cards.length * 70 + 420);
      overlay.remove();
    };
    const watch = new IntersectionObserver((entries) => {
      if (!entries.some((entry) => entry.isIntersecting)) return;
      watch.disconnect();
      play();
    }, { threshold: 0.5 });
    watch.observe(typing);
  }

  // GitHub stars, live: the count once the repository is public, else "Star on GitHub". The count
  // is kept for an hour, as GitHub allows a visitor sixty unsigned requests an hour.
  const KEY = 'erst-stars';
  function show(count) {
    if (!(count > 0)) return;
    const text = count >= 1000 ? `${(count / 1000).toFixed(count >= 10000 ? 0 : 1).replace(/\.0$/, '')}k` : String(count);
    document.querySelectorAll('[data-stars]').forEach((link) => {
      const label = link.querySelector('[data-star-label]');
      const number = document.createElement('b');
      number.textContent = text;
      label.replaceChildren(number, count === 1 ? ' GitHub star' : ' GitHub stars');
      link.setAttribute('aria-label', `Erst on GitHub, ${count} ${count === 1 ? 'star' : 'stars'}`);
    });
  }
  try {
    const cached = JSON.parse(localStorage.getItem(KEY) || 'null');
    if (cached && Date.now() - cached.at < 3600_000) show(cached.count);
    else fetch('https://api.github.com/repos/zqkra/erst', { headers: { Accept: 'application/vnd.github+json' } })
      .then((r) => (r.ok ? r.json() : null))
      .then((repo) => {
        if (!repo) return;
        localStorage.setItem(KEY, JSON.stringify({ count: repo.stargazers_count, at: Date.now() }));
        show(repo.stargazers_count);
      })
      .catch(() => {});
  } catch { /* storage blocked: keep "Star on GitHub" */ }
})();
