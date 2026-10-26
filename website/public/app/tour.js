/* ================= APT TOUR — bubble coachmarks (v1.1.92) =================
   Spotlight-cuts the target out of a dark scrim, pins a bubble next to it,
   steps the user through one screen at a time (home → floor → menu → more).
   Locales EN/UR come from L.t(); state survives in kv so it runs once until
   re-invoked manually from More → "Guide me".
*/
(function () {
  const kvGet = window.kvGet, kvSet = window.kvSet, L = window.OFLang;

  const STEPS = [
    {
      tab: 'home', sel: '[data-tour="hero"]', fallbackSel: '#tab-home .card, #tab-home',
      title: L.t('tour_home_t'), body: L.t('tour_home_b'),
    },
    {
      tab: 'home', sel: '[data-act="home.roomqr"]', fallbackSel: '[data-tour="room"]',
      title: L.t('tour_room_t'), body: L.t('tour_room_b'),
    },
    {
      tab: 'floor', sel: '#tab-floor', pos: 'top', backdrop: true,
      title: L.t('tour_floor_t'), body: L.t('tour_floor_b'),
    },
    {
      tab: 'menu', sel: '#tab-menu .mcard, #tab-menu', pos: 'top',
      title: L.t('tour_menu_t'), body: L.t('tour_menu_b'),
    },
    {
      tab: 'more', sel: '#tab-more', pos: 'top',
      title: L.t('tour_more_t'), body: L.t('tour_more_b'),
    },
    {
      tab: null, sel: '#bnav .bnav__dest[data-tab-id="home"], #rail', pos: 'center',
      title: L.t('tour_done_t'), body: L.t('tour_done_b'),
    },
  ];

  let overlay = null, stepIdx = 0, activeTabBefore = null, running = false;

  function el(q) { return document.querySelector(q); }
  function prefersReduced() { return window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches; }

  async function maybeStart() {
    try {
      const done = await kvGet('tourSeen', false);
      if (done) return;
      // Only on Main's main UI — the license/setup screens come before.
      if (!el('#view-main') || el('#view-main').hidden) {
        setTimeout(maybeStart, 2500);
        return;
      }
      start();
    } catch { }
  }

  async function start(fromMore) {
    if (running) return;
    running = true; stepIdx = 0;
    activeTabBefore = window.__ofActiveTab || 'home';
    buildOverlay();
    renderStep();
    if (!fromMore) { try { await kvSet('tourSeen', true); } catch { } }
    window.addEventListener('resize', onResize);
  }

  function onResize() { if (running && overlay) positionStep(); }

  function buildOverlay() {
    if (overlay) overlay.remove();
    overlay = document.createElement('div');
    overlay.id = 'of-tour';
    overlay.innerHTML =
      '<div class="tour-mask" aria-hidden="true"></div>'
      + '<div class="tour-hole" aria-hidden="true"></div>'
      + '<div class="tour-bubble" role="dialog" aria-live="polite">'
      + '  <div class="tour-bubble__t" id="tour-title"></div>'
      + '  <div class="tour-bubble__b" id="tour-body"></div>'
      + '  <div class="tour-bubble__nav">'
      + '    <button class="tour-skip" id="tour-skip">' + L.t('tour_skip') + '</button>'
      + '    <span class="tour-dots" id="tour-dots"></span>'
      + '    <button class="tour-next" id="tour-next">' + L.t('tour_next') + '</button>'
      + '  </div>'
      + '</div>';
    document.body.appendChild(overlay);
    overlay.querySelector('#tour-skip').onclick = stop;
    overlay.querySelector('#tour-next').onclick = next;
    overlay.querySelector('.tour-mask').onclick = next;
    if (!prefersReduced()) overlay.classList.add('tour-anim');
  }

  function stop() {
    running = false;
    window.removeEventListener('resize', onResize);
    if (overlay) { overlay.remove(); overlay = null; }
    try { kvSet('tourSeen', true); } catch { }
  }

  function step() { return STEPS[stepIdx]; }

  function findTarget(s) {
    if (!s.sel) return null;
    for (const part of s.sel.split(',')) {
      const el = el(part.trim());
      if (el && el.offsetParent !== null) return el;
    }
    if (s.fallbackSel) {
      for (const part of s.fallbackSel.split(',')) {
        const el = el(part.trim());
        if (el && el.offsetParent !== null) return el;
      }
    }
    return null;
  }

  function ensureTab(tab) {
    if (!tab) return Promise.resolve();
    return new Promise(res => {
      const want = el('[data-tab-id="' + tab + '"]');
      if (want && !want.classList.contains('is-on')) {
        try { want.click(); } catch { }
      }
      // one frame so the target is laid out
      requestAnimationFrame(() => setTimeout(res, 60));
    });
  }

  async function renderStep() {
    const s = step();
    if (!s) return stop();
    await ensureTab(s.tab);
    positionStep();
    document.getElementById('tour-title').textContent = s.title;
    document.getElementById('tour-body').textContent = s.body;
    document.getElementById('tour-dots').innerHTML = STEPS.map((_, i) =>
      '<i class="' + (i === stepIdx ? 'is-on' : (i < stepIdx ? 'is-done' : '')) + '"></i>').join('');
    document.getElementById('tour-next').textContent = stepIdx === STEPS.length - 1 ? L.t('tour_end') : L.t('tour_next');
  }

  function positionStep() {
    if (!overlay || !running) return;
    const s = step();
    const hole = overlay.querySelector('.tour-hole');
    const bubble = overlay.querySelector('.tour-bubble');
    const target = findTarget(s);
    hole.style.display = 'none'; bubble.classList.remove('tour-up', 'tour-down');
    if (target && s.pos !== 'center') {
      const r = target.getBoundingClientRect();
      const pad = 8;
      hole.style.display = 'block';
      hole.style.left = (r.left - pad) + 'px';
      hole.style.top = (r.top - pad) + 'px';
      hole.style.width = (r.width + pad * 2) + 'px';
      hole.style.height = (r.height + pad * 2) + 'px';
      // bubble above or below, prefer whichever has room
      const bw = Math.min(340, window.innerWidth - 24);
      const bh = 150; // estimated
      const belowFits = r.bottom + 16 + bh < window.innerHeight - 80;
      const left = Math.max(12, Math.min(window.innerWidth - bw - 12, r.left + r.width / 2 - bw / 2));
      if (s.pos === 'top' || !belowFits) {
        bubble.style.top = Math.max(12, r.top - bh - 16) + 'px';
        bubble.classList.add('tour-up');
      } else {
        bubble.style.top = (Math.min(window.innerHeight - bh - 12, r.bottom + 16)) + 'px';
        bubble.classList.add('tour-down');
      }
      bubble.style.left = left + 'px';
      bubble.style.width = bw + 'px';
    } else {
      // center fallback
      bubble.style.top = '50%';
      bubble.style.left = '50%';
      bubble.style.transform = 'translate(-50%,-50%)';
      bubble.style.width = Math.min(360, window.innerWidth - 24) + 'px';
      bubble.classList.add('tour-center');
    }
  }

  function next() {
    stepIdx++;
    if (stepIdx >= STEPS.length) return stop();
    renderStep();
  }

  // publics
  window.OFTour = { start: () => start(true), restart: start, stop, maybeStart };
  document.addEventListener('DOMContentLoaded', () => setTimeout(maybeStart, 1800));
})();
