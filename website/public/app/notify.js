/* ============================================================
   ORDER FLOW — NOTIFICATIONS + AUTO-UPDATE v40 (additive)
   ----------------------------------------------------------------
   •asks permission once (gesture-safe), then fires SYSTEM
    notifications on the app's real event hooks (new ticket,
    ready, paid) with loud WebAudio alert + vibration pattern.
   • iPhone note: system notifications require the app INSTALLED
     to home screen (iOS 16.4+); in a plain Safari tab we keep
     the in-app chime/buzz fallback (already in app.js).
   •register the PWA service worker and self-update it; plus a
    build-oracle (ver.txt) — when the server has a newer build
    and the screen is calm, banner "tap to update", and if the
    SW swaps in a new controller we reload once automatically.
   ============================================================ */
(function () {
  'use strict';

  var REG = null;
  var bannerShown = false;

  /* ---------------- service worker ---------------- */
  function bootSW() {
    if (!('serviceWorker' in navigator)) return;
    navigator.serviceWorker.register('/sw.js', { scope: '/' }).then(function (r) {
      REG = r;
      try { r.update(); } catch (e) {}
      setInterval(function () { if (document.visibilityState === 'visible') { try { r.update(); } catch (e) {} } }, 60000);
    }).catch(function () {});
    var reloaded = false;
    navigator.serviceWorker.addEventListener('controllerchange', function () {
      if (reloaded) return; reloaded = true;
      try { sessionStorage.setItem('of_sw_swap', '1'); } catch (e) {}
      location.reload();
    });
  }

  /* ---------------- loud alert (WebAudio, no asset) ---------------- */
  function loudAlert(kind) {
    try {
      var Ctx = window.AudioContext || window.webkitAudioContext; if (!Ctx) return;
      var ctx = loudAlert._ctx || (loudAlert._ctx = new Ctx());
      if (ctx.state === 'suspended') ctx.resume();
      var t = ctx.currentTime, seq = kind === 'ready' ? [880, 1320, 1760] : kind === 'paid' ? [990, 1480] : [740, 1180, 1560, 1180, 1560];
      seq.forEach(function (f, i) {
        var o = ctx.createOscillator(), g = ctx.createGain();
        o.type = 'square'; o.frequency.value = f;
        g.gain.setValueAtTime(0.0001, t + i * 0.14);
        g.gain.exponentialRampToValueAtTime(0.85, t + i * 0.14 + 0.02);
        g.gain.exponentialRampToValueAtTime(0.0001, t + i * 0.14 + 0.12);
        o.connect(g); g.connect(ctx.destination);
        o.start(t + i * 0.14); o.stop(t + i * 0.14 + 0.13);
      });
    } catch (e) {}
  }

  /* ---------------- permission ---------------- */
  function state() { return ('Notification' in window) ? Notification.permission : 'denied'; }
  function ensurePromptLater() {
    if (state() !== 'default') return;
    if (localStorage.getItem('of_notif_declined') === '1') return;
    /* show the bell sheet the FIRST time the main shell appears */
    var iv = setInterval(function () {
      var main = document.getElementById('view-main') || document.getElementById('view-rolehome');
      if (!main || main.hidden) return;
      clearInterval(iv);
      setTimeout(showAsk, 1400);
    }, 1200);
    setTimeout(function () { clearInterval(iv); }, 60000);
  }
  function showAsk() {
    if (state() !== 'default') return;
    if (document.getElementById('of-ask')) return;
    var bar = document.createElement('div');
    bar.id = 'of-ask';
    bar.style.cssText = 'position:fixed;left:14px;right:14px;bottom:calc(86px + env(safe-area-inset-bottom,0px));z-index:70;max-width:560px;margin:0 auto;' +
      'background:var(--surface);color:var(--ink);border:1.4px solid var(--border);border-radius:18px;box-shadow:var(--shadow);' +
      'display:flex;align-items:center;gap:12px;padding:14px 16px;animation:ofPop .4s cubic-bezier(.22,1.35,.34,1) both;';
    bar.innerHTML = '<style>@keyframes ofPop{from{opacity:0;transform:translateY(18px) scale(.96)}to{opacity:1;transform:none}}</style>' +
      '<div style="font-size:26px;line-height:1">🔔</div>' +
      '<div style="flex:1 1 auto;min-width:0"><div style="font-weight:900;font-size:14.5px">Loud alerts for new tickets?</div>' +
      '<div style="font-weight:600;font-size:12px;color:var(--muted);margin-top:2px">System notification + strong vibration, even when your phone is in your pocket.' +
      (/(iphone|ipad|ipod)/i.test(navigator.userAgent) ? ' Tip: install the app to your home screen for full iPhone notifications.' : '') + '</div></div>' +
      '<button id="of-ask-no" style="border:0;background:none;color:var(--muted);font-weight:800;padding:10px 6px">Later</button>' +
      '<button id="of-ask-yes" style="border:0;border-radius:12px;background:var(--mint);color:#07130D;font-weight:900;padding:11px 16px">Turn on</button>';
    document.body.appendChild(bar);
    bar.querySelector('#of-ask-no').onclick = function () { try { localStorage.setItem('of_notif_declined', '1'); } catch (e) {} bar.remove(); };
    bar.querySelector('#of-ask-yes').onclick = function () {
      bar.remove();
      try { Notification.requestPermission().then(function (p) { if (p === 'granted') { loudAlert('ticket'); notify('ticket', "You're all set", 'Alerts for new tickets are ON'); } }); } catch (e) {}
    };
  }

  /* ---------------- the notifier ---------------- */
  function notify(kind, title, body) {
    loudAlert(kind);
    try { if (navigator.vibrate) navigator.vibrate(kind === 'ticket' ? [350, 120, 350, 120, 600] : [180, 80, 260]); } catch (e) {}
    if (state() !== 'granted') return;
    var opts = {
      body: body || '', icon: '/media/logo.png', badge: '/media/logo.png',
      tag: 'of-' + kind, renotify: true, silent: false,
      requireInteraction: kind === 'ticket',
      vibrate: kind === 'ticket' ? [350, 120, 350, 120, 600] : [180, 80, 260]
    };
    if (REG && REG.showNotification) { try { REG.showNotification(title, opts); return; } catch (e) {} }
    try { var n = new Notification(title, opts); n.onclick = function () { try { window.focus(); } catch (e) {} }; } catch (e) {}
  }

  /* ---------------- auto-update oracle ---------------- */
  function currentBuild() {
    const marker = document.querySelector('meta[name="of-build"]');
    return String(window.OF_BUILD || (marker && marker.content) || '');
  }
  function checkServerBuild() {
    if (!currentBuild() || bannerShown) return;
    fetch('/app/ver.txt?ts=' + Date.now(), { cache: 'no-store' }).then(function (r) {
      return r.ok ? r.text() : '';
    }).then(function (t) {
      t = (t || '').trim();
      if (t && currentBuild() && t !== currentBuild() && !bannerShown) showUpdateBar();
    }).catch(function () {});
  }
  function showUpdateBar() {
    bannerShown = true;
    var bar = document.createElement('div');
    bar.style.cssText = 'position:fixed;top:calc(10px + env(safe-area-inset-top,0px));left:50%;transform:translateX(-50%);z-index:95;' +
      'background:var(--btn-forest);color:#fff;border-radius:999px;box-shadow:0 14px 32px rgba(0,0,0,.3);' +
      'display:flex;align-items:center;gap:10px;padding:10px 16px;font-weight:900;font-size:13.5px;white-space:nowrap;max-width:92vw;';
    bar.innerHTML = '<svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M21 12a9 9 0 1 1-3-6.7"/><path d="M21 3v5h-5"/></svg> Update ready — tap to refresh';
    bar.onclick = function () { location.reload(); };
    document.body.appendChild(bar);
  }

  /* ---------------- boot ---------------- */
  function boot() {
    bootSW();
    ensurePromptLater();
    checkServerBuild();
    setInterval(checkServerBuild, 5 * 60 * 1000);
    document.addEventListener('visibilitychange', function () { if (document.visibilityState === 'visible') checkServerBuild(); });
    window.OFNotify = { notify: notify, supported: function () { return state(); } };
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot); else boot();
})();
