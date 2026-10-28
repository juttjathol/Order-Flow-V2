/* ================= APP TOUR — bubble coachmarks (v1.1.93 element-level) ====
   Goes TO the button: every step spots a real control (new-ticket button,
   room QR button, pay button, kitchen badge) — never just a page. The
   spotlight rectangles the live element, scrolls it into view, and the
   bubble docks right beside it. Locales EN/UR via L.t().
*/
(function () {
  const kvGet = window.kvGet, kvSet = window.kvSet, L = window.OFLang;

  const STEPS = [
    {
      tab: 'home',
      sel: '[data-tour="hero"]',
      fallbackSel: '#tab-home .card.card--forest.hero, #tab-home .card, #tab-home',
      title: L.t('tour_home_t'), body: L.t('tour_home_b'),
    },
    {
      tab: 'home',
      sel: '[data-act="home.roomqr"]',
      fallbackSel: '[data-tour="room"], #tab-home [data-act^="home."]',
      title: L.t('tour_room_t'), body: L.t('tour_room_b'),
    },
    {
      tab: 'floor',
      sel: '#tab-floor .tcard:not(.tcard--free), #tab-floor .tcard, #tab-floor .btn--primary',
      fallbackSel: '#tab-floor',
      title: L.t('tour_floor_t'), body: L.t('tour_floor_b'),
    },
    {
      tab: 'menu',
      sel: '#tab-menu .mcard .mcard__add, #tab-menu .mcard, #tab-menu [data-act^="menu."], #tab-menu .btn--primary',
      fallbackSel: '#tab-menu',
      title: L.t('tour_menu_t'), body: L.t('tour_menu_b'),
    },
    {
      tab: 'more',
      sel: '#tab-more [data-act="more.cloud"], #tab-more [data-act="more.bill"], #tab-more .accs',
      fallbackSel: '#tab-more',
      title: L.t('tour_more_t'), body: L.t('tour_more_b'),
      preferBottomSheet: true,
    },
    {
      tab: null,
      sel: '#bnav .bnav__dest[data-tab-id="home"], #rail',
      fallbackSel: '#bnav',
      pos: 'center',
      title: L.t('tour_done_t'), body: L.t('tour_done_b'),
    },
  ];

  let overlay = null, stepIdx = 0, running = false;

  function el(q) { return document.querySelector(q); }
  function prefersReduced() { return window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches; }

  async function maybeStart() {
    try {
      const done = await kvGet('tourSeen', false);
      if (done) return;
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
    buildOverlay();
    await renderStep();
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
      const t = el(part.trim());
      if (t && t.offsetParent !== null) return t;
    }
    if (s.fallbackSel) {
      for (const part of s.fallbackSel.split(',')) {
        const t = el(part.trim());
        if (t && t.offsetParent !== null) return t;
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
      requestAnimationFrame(() => setTimeout(res, 120));
    });
  }

  async function renderStep() {
    const s = step();
    if (!s) return stop();
    await ensureTab(s.tab);
    const target = findTarget(s);
    if (target && target.scrollIntoView) {
      // Bring the button into view before measuring (fixed nav overlays the bottom).
      try { target.scrollIntoView({ block: 'center', behavior: prefersReduced() ? 'auto' : 'smooth' }); } catch { }
    }
    // after scroll animation settles (~220 ms), measure + position
    setTimeout(positionStep, prefersReduced() ? 0 : 240);
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
    hole.style.display = 'none'; bubble.classList.remove('tour-up', 'tour-down', 'tour-center');
    bubble.style.transform = 'none';
    if (target && s.pos !== 'center') {
      const r = target.getBoundingClientRect();
      if (r.width === 0 && r.height === 0) { // removed mid-scroll — recentre
        bubble.classList.add('tour-center');
        bubble.style.top = '50%'; bubble.style.left = '50%';
        bubble.style.transform = 'translate(-50%,-50%)';
        bubble.style.width = Math.min(360, window.innerWidth - 24) + 'px';
        return;
      }
      const pad = 8;
      hole.style.display = 'block';
      hole.style.left = Math.max(4, r.left - pad) + 'px';
      hole.style.top = Math.max(4, r.top - pad) + 'px';
      hole.style.width = Math.min(window.innerWidth - 8, r.width + pad * 2) + 'px';
      hole.style.height = Math.min(window.innerHeight - 8, r.height + pad * 2) + 'px';
      const bw = Math.min(340, window.innerWidth - 24);
      const bh = bubble.offsetHeight || 168;
      const belowFits = r.bottom + 12 + bh < window.innerHeight - 84;
      const aboveFits = r.top - 12 - bh > 8;
      const left = Math.max(12, Math.min(window.innerWidth - bw - 12, r.left + r.width / 2 - bw / 2));
      if (aboveFits && !belowFits) {
        bubble.style.top = Math.max(12, r.top - bh - 12) + 'px';
        bubble.classList.add('tour-up');
      } else if (s.preferBottomSheet) {
        // More tab rows: the visible card sits near the top — bubble sits centered below.
        bubble.style.top = Math.min(window.innerHeight - bh - 12, r.bottom + 16) + 'px';
        bubble.classList.add('tour-down');
      } else if (belowFits) {
        bubble.style.top = Math.min(window.innerHeight - bh - 12, r.bottom + 12) + 'px';
        bubble.classList.add('tour-down');
      } else {
        bubble.style.top = '50%';
        bubble.style.left = '50%';
        bubble.style.transform = 'translate(-50%,-50%)';
        bubble.classList.add('tour-center');
      }
      bubble.style.left = left + 'px';
      bubble.style.width = bw + 'px';
    } else {
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

  window.OFTour = { start: () => start(true), restart: start, stop, maybeStart };
  document.addEventListener('DOMContentLoaded', () => setTimeout(maybeStart, 1800));
})();
