/* ============================================================
   ORDER FLOW — MOTION ENGINE v39 (standalone, logic-free)
   ----------------------------------------------------------------
   • Owns the `html[data-motion]` tier: full | low | off.
   • Adaptive per-device: prefers-reduced-motion → off; weak
     hardware starts low; a live FPS governor can only ever
     DOWNGRADE a device (sticky), so an old phone stays smooth
     while flagship users keep the full show.
   • Zero edits to app/core/more/ticket js: everything is wired
     with observers + delegated events. If anything throws, we
     snap to "off" and the app behaves exactly as before.
   • Manual control: OFMotion.set('full'|'low'|'off') in console.
   ============================================================ */
(function () {
  'use strict';

  var LS_KEY = 'of_motion_tier_v1';
  var TIER = 'off';
  var TABS = ['home', 'floor', 'menu', 'stock', 'more'];
  var lastTabIdx = 0;
  var isAnimCapable = true;

  function root() { return document.documentElement; }

  /* ---------------- tier control ---------------- */
  function setTier(t, persist) {
    if (t !== 'full' && t !== 'low' && t !== 'off') t = 'off';
    TIER = t;
    root().dataset.motion = t;
    if (persist) { try { localStorage.setItem(LS_KEY, t); } catch (e) {} }
  }

  /* ---------------- FPS governor (sticky downgrades) --------- */
  function sample(ms, cb) {
    var n = 0, t0 = 0;
    function f(ts) {
      if (!t0) t0 = ts;
      n++;
      if (ts - t0 < ms) { requestAnimationFrame(f); }
      else cb(Math.round(n / ((ts - t0) / 1000)));
    }
    requestAnimationFrame(f);
  }
  var probing = false;
  function governor(windowMs) {
    if (probing || TIER === 'off' || !isAnimCapable) return;
    probing = true;
    sample(windowMs || 900, function (fps) {
      probing = false;
      try {
        if (TIER === 'full' && fps < 40) setTier(fps < 26 ? 'off' : 'low', true);
        else if (TIER === 'low' && fps < 26) setTier('off', true);
      } catch (e) { setTier('off'); }
    });
  }

  /* ---------------- choreography helpers ---------------- */
  function enterView(el) {
    if (TIER === 'off') return;
    el.classList.remove('mo-in');
    void el.offsetWidth;               /* restart animation cleanly */
    el.classList.add('mo-in');
    setTimeout(function () { el.classList.remove('mo-in'); }, 700);
    staggerView(el);
  }
  function staggerView(el) {
    if (TIER !== 'full') return;
    var lists = el.querySelectorAll('.grid,.tiles,.stats,.tmap,.mgrid,.accs,.typechips');
    for (var a = 0; a < lists.length; a++) {
      var list = lists[a], kids = list.children;
      var cap = Math.min(kids.length, 12);
      for (var i = 0; i < cap; i++) {
        kids[i].style.setProperty('--i', String(i));
      }
      list.classList.add('mo-stack');
      (function (l, k, c) {
        setTimeout(function () {
          l.classList.remove('mo-stack');
          for (var j = 0; j < c; j++) k[j].style.removeProperty('--i');
        }, 1100 + c * 40);
      })(list, kids, cap);
    }
  }
  function tabIn(el) {
    if (TIER === 'off') return;
    var idx = TABS.indexOf(el.id.slice(4));
    var dir = idx >= lastTabIdx ? 1 : -1;
    if (idx >= 0) lastTabIdx = idx;
    var rtl = getComputedStyle(root()).direction === 'rtl';
    el.style.setProperty('--mo-dir', String(rtl ? -dir : dir));
    el.classList.remove('mo-tabin');
    void el.offsetWidth;
    el.classList.add('mo-tabin');
    setTimeout(function () { el.classList.remove('mo-tabin'); }, 520);
    staggerView(el);
  }
  function kick(el, cls, ms) {
    if (TIER !== 'full' || !el) return;
    el.classList.remove(cls); void el.offsetWidth; el.classList.add(cls);
    setTimeout(function () { el.classList.remove(cls); }, ms);
  }

  /* ---------------- observers ---------------- */
  var selTarget = null;
  function nodeEl(m) {
    var t = m.target;
    return t && t.nodeType === 1 ? t : (t && t.parentElement);
  }
  function watchAll() {
    /* 1 — view / gate / tab entrances */
    var visObs = new MutationObserver(function (ms) {
      for (var i = 0; i < ms.length; i++) {
        var el = ms[i].target;
        if (el.hidden) continue;
        try {
          if (el.classList.contains('view') || el.classList.contains('gate')) enterView(el);
          else if (/^tab-(home|floor|menu|stock|more)$/.test(el.id)) tabIn(el);
        } catch (e) {}
      }
      governor(900);                    /* probe once per switch wave */
    });
    var watch = '.view,.gate,#tab-home,#tab-floor,#tab-menu,#tab-stock,#tab-more';
    document.querySelectorAll(watch).forEach(function (el) {
      visObs.observe(el, { attributes: true, attributeFilter: ['hidden'], subtree: false });
    });

    /* 2 — kinetic text: totals, stats, header labels */
    var lastTxt = new WeakMap();
    var NUM_SEL = '.hero__amt,.stat__v,.cdisp__total,[data-kinetic]';
    var HDR_SEL = '.hdr__title,.hdr__sub,#hdr-shop,#hdr-role';
    var txtObs = new MutationObserver(function (ms) {
      if (TIER !== 'full') return;
      for (var i = 0; i < ms.length; i++) {
        var el = nodeEl(ms[i]);
        if (!el || el.closest('input,textarea,[contenteditable]')) continue;
        try {
          var t = el.closest(NUM_SEL);
          if (t && lastTxt.get(t) !== t.textContent) { lastTxt.set(t, t.textContent); kick(t, 'mo-tick', 420); continue; }
          var h = el.closest(HDR_SEL);
          if (h && lastTxt.get(h) !== h.textContent) { lastTxt.set(h, h.textContent); kick(h, 'mo-hfade', 380); }
        } catch (e) {}
      }
    });
    txtObs.observe(document.body, { characterData: true, childList: true, subtree: true });
  }

  /* ---------------- press springs (delegated) ---------------- */
  var PRESS_SEL = '.btn,.tile,.tcard,.mcard,.fchip,.mrow,.lrow,.iconbtn,.modelcard,.numpad button,.mcard__add,.readyline button,.qtyctl button,.typechips button,.chip,.bnav__dest,.rail__dest';
  var pressed = null;
  function releasePress() {
    if (pressed) { var el = pressed; pressed = null; setTimeout(function () { el.classList.remove('mo-press'); }, 40); }
  }
  function wirePress() {
    document.addEventListener('pointerdown', function (e) {
      if (TIER === 'off') return;
      var el = e.target && e.target.closest ? e.target.closest(PRESS_SEL) : null;
      if (!el || el.disabled || el.classList.contains('disabled')) return;
      pressed = el; el.classList.add('mo-press');
    }, true);
    ['pointerup', 'pointercancel', 'pointerleave'].forEach(function (ev) {
      document.addEventListener(ev, releasePress, true);
    });
  }

  /* ---------------- boot ---------------- */
  function boot() {
    try {
      var saved = null; try { saved = localStorage.getItem(LS_KEY); } catch (e) {}
      var prm = false; try { prm = matchMedia('(prefers-reduced-motion: reduce)').matches; } catch (e) {}
      if (prm) { setTier('off'); }
      else if (saved) { setTier(saved); }
      else {
        var hc = navigator.hardwareConcurrency || 4;
        var dm = navigator.deviceMemory || 8;
        setTier((hc <= 2 || dm <= 2) ? 'low' : 'full');
      }
      isAnimCapable = TIER !== 'off';
      if (TIER !== 'off') {
        /* startup probe after first paint settles */
        setTimeout(function () { governor(1200); }, 700);
      }
      watchAll();
      wirePress();
      window.OFMotion = {
        tier: function () { return TIER; },
        set: function (t) { setTier(t, true); isAnimCapable = t !== 'off'; },
        probe: function () { governor(1200); }
      };
    } catch (e) { setTier('off'); }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else boot();
})();
