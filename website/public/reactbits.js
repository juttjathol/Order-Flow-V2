/* v1.1.63 site · React Bits pack — vanilla recreations of reactbits.dev
   signature animations: DecryptedText, BlurText, SpotlightCard, GlareHover,
   BorderGlow, Sparkles, Magnet, AnimatedContent, ShinyText touches.
   Purely additive: html.rbits gates everything; no script or
   prefers-reduced-motion → the page stays exactly as it shipped. */
(() => {
  "use strict";
  if (matchMedia("(prefers-reduced-motion: reduce)").matches) return;
  const root = document.documentElement;
  root.classList.add("rbits");
  const fine = matchMedia("(pointer:fine)").matches;

  /* ── 1 · DecryptedText — hero title, then the download heading ─────────
     Chars are grouped into nowrap word boxes so scrambling can never
     introduce a mid-word line break on narrow screens. */
  const GLYPHS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ#%&*+=/<>0123456789";
  function decrypt(el) {
    if (!el || el.dataset.rbDec) return;
    el.dataset.rbDec = "1";
    const nodes = [];
    (function walk(n) {
      for (const c of n.childNodes) {
        if (c.nodeType === 3 && c.textContent.length) nodes.push(c);
        else if (c.nodeType === 1) walk(c);
      }
    })(el);
    let i = 0;
    for (const tn of nodes) {
      const frag = document.createDocumentFragment();
      const queue = [];
      for (const part of tn.textContent.split(/(\s+)/)) {
        if (!part) continue;
        if (/^\s+$/.test(part)) { frag.appendChild(document.createTextNode(part)); continue; }
        const w = document.createElement("span");
        w.className = "rb-w";
        for (const ch of part) {
          const s = document.createElement("span");
          s.className = "rb-ch";
          s.textContent = ch;
          w.appendChild(s);
          if (ch.trim()) queue.push(s);
        }
        frag.appendChild(w);
      }
      tn.parentNode.replaceChild(frag, tn);
      for (const s of queue) {
        const orig = s.textContent;
        const startAt = (i++) * 14;
        setTimeout(() => {
          s.classList.add("rb-s");
          const dur = 170 + Math.floor(Math.random() * 180);
          const ticker = setInterval(() => {
            s.textContent = GLYPHS[(Math.random() * GLYPHS.length) | 0];
          }, 40);
          setTimeout(() => {
            clearInterval(ticker);
            s.textContent = orig;
            s.classList.remove("rb-s");
          }, dur);
        }, startAt);
      }
    }
  }
  const heroH1 = document.querySelector(".hero h1");
  if (heroH1) requestAnimationFrame(() => setTimeout(() => decrypt(heroH1), 260));
  const dlTitle = document.querySelector(".download-band .sec-title");
  if (dlTitle && "IntersectionObserver" in window) {
    const dio = new IntersectionObserver((rows) => {
      for (const r of rows) {
        if (!r.isIntersecting) continue;
        dio.unobserve(r.target);
        decrypt(r.target);
      }
    }, { threshold: 0.5 });
    dio.observe(dlTitle);
  }

  /* ── 2 · BlurText — section titles land word-by-word out of the blur ─── */
  const blurTargets = [...document.querySelectorAll("h2.sec-title")]
    .filter((el) => el !== dlTitle && !el.closest("[data-rb-noblur]"));
  for (const el of blurTargets) {
    const text = el.textContent;
    el.setAttribute("aria-label", text);
    el.textContent = "";
    const words = text.split(/\s+/).filter(Boolean);
    words.forEach((w, k) => {
      const s = document.createElement("span");
      s.className = "rb-word";
      s.textContent = w;
      s.style.setProperty("--d", (k * 0.045).toFixed(3) + "s");
      el.appendChild(s);
      if (k < words.length - 1) el.appendChild(document.createTextNode(" "));
    });
  }
  if ("IntersectionObserver" in window && blurTargets.length) {
    const bio = new IntersectionObserver((rows) => {
      for (const r of rows) {
        if (!r.isIntersecting) continue;
        bio.unobserve(r.target);
        r.target.classList.add("rb-on");
      }
    }, { threshold: 0.25 });
    blurTargets.forEach((el) => bio.observe(el));
  } else {
    blurTargets.forEach((el) => el.classList.add("rb-on"));
  }

  /* ── 3 · SpotlightCard — mint light pool trails the pointer ─────────── */
  if (fine) {
    const spots = [...document.querySelectorAll(".card, .plan")];
    for (const el of spots) {
      el.classList.add("rb-spot");
      let raf = 0, lx = 0, ly = 0;
      el.addEventListener("pointermove", (e) => {
        const r = el.getBoundingClientRect();
        lx = ((e.clientX - r.left) / r.width) * 100;
        ly = ((e.clientY - r.top) / r.height) * 100;
        if (raf) return;
        raf = requestAnimationFrame(() => {
          raf = 0;
          el.style.setProperty("--sx", lx.toFixed(1) + "%");
          el.style.setProperty("--sy", ly.toFixed(1) + "%");
        });
      }, { passive: true });
    }
  }

  /* ── 4 · GlareHover — CSS sweep on hover + one auto-ping on CTAs ─────── */
  const ping = (btn, delay) => {
    if (!btn) return;
    setTimeout(() => {
      btn.classList.add("rb-ping");
      setTimeout(() => btn.classList.remove("rb-ping"), 1000);
    }, delay);
  };
  const heroBtns = document.querySelectorAll(".hero-actions .btn");
  heroBtns.forEach((b, k) => ping(b, 1500 + k * 260));
  if ("IntersectionObserver" in window) {
    const gio = new IntersectionObserver((rows) => {
      for (const r of rows) {
        if (!r.isIntersecting) continue;
        gio.unobserve(r.target);
        ping(document.getElementById("dl-btn"), 700);
      }
    }, { threshold: 0.5 });
    const band = document.querySelector(".download-band");
    if (band) gio.observe(band);
  }

  /* ── 5 · BorderGlow — light beam orbits the download band ────────────── */
  const glow = document.querySelector(".download-band");
  if (glow) {
    glow.classList.add("rb-glow");
    let vis = false;
    let raf = 0;
    const spin = () => {
      if (!vis) { raf = 0; return; }
      const deg = (performance.now() / 42) % 360;
      glow.style.setProperty("--rba", deg.toFixed(1) + "deg");
      raf = requestAnimationFrame(spin);
    };
    if ("IntersectionObserver" in window) {
      const vio = new IntersectionObserver((rows) => {
        for (const r of rows) vis = r.isIntersecting;
        if (vis && !raf) raf = requestAnimationFrame(spin);
      }, { threshold: 0.05 });
      vio.observe(glow);
    } else {
      vis = true; raf = requestAnimationFrame(spin);
    }
  }

  /* ── 6 · AnimatedContent — the hero meta tiles rise in, staggered ────── */
  const metaKids = document.querySelectorAll(".meta-row > div");
  if (metaKids.length) {
    requestAnimationFrame(() => {
      metaKids.forEach((el, k) => {
        el.style.animationDelay = (0.85 + k * 0.13).toFixed(2) + "s";
        el.classList.add("rb-anim");
      });
    });
  }

  /* ── 7 · Magnet — hero + download CTAs lean toward the cursor ────────── */
  if (fine) {
    for (const el of document.querySelectorAll(".hero-actions .btn, .dl-actions .btn, .trial-form .btn")) {
      let raf = 0, tx = 0, ty = 0;
      el.addEventListener("pointermove", (e) => {
        const r = el.getBoundingClientRect();
        tx = ((e.clientX - (r.left + r.width / 2)) / (r.width / 2)) * 13;
        ty = ((e.clientY - (r.top + r.height / 2)) / (r.height / 2)) * 8;
        tx = Math.max(-13, Math.min(13, tx));
        ty = Math.max(-8, Math.min(8, ty));
        if (raf) return;
        raf = requestAnimationFrame(() => {
          raf = 0;
          el.style.transform = `translate(${tx.toFixed(1)}px, ${ty.toFixed(1)}px)`;
        });
      }, { passive: true });
      el.addEventListener("pointerleave", () => {
        if (raf) { cancelAnimationFrame(raf); raf = 0; }
        el.style.transition = "transform .45s cubic-bezier(.2,.8,.2,1)";
        el.style.transform = "";
        setTimeout(() => { el.style.transition = ""; }, 480);
      });
    }
  }

  /* ── 8 · Sparkles — mint embers drift up through the hero (canvas) ───── */
  const hero = document.querySelector(".hero");
  if (hero) {
    const cv = document.createElement("canvas");
    cv.className = "rb-spark";
    hero.appendChild(cv);
    const ctx = cv.getContext && cv.getContext("2d");
    if (!ctx) {
      cv.remove();
    } else {
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      let w = 0, h = 0, parts = [], vis = true, raf = 0, last = 0;
      const size = () => {
        w = hero.clientWidth || 1; h = hero.clientHeight || 1;
        cv.width = w * dpr; cv.height = h * dpr;
        ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
        const n = w < 700 ? 24 : 46;
        parts = Array.from({ length: n }, () => ({
          x: Math.random() * w, y: Math.random() * h,
          r: 0.6 + Math.random() * 1.5,
          vy: 6 + Math.random() * 12, vx: (Math.random() - 0.5) * 5,
          ph: Math.random() * 6.283, sp: 1 + Math.random() * 2,
        }));
      };
      size();
      addEventListener("resize", size, { passive: true });
      const frame = (t) => {
        raf = 0;
        if (!vis || document.hidden) return;
        const dt = Math.min((t - last) / 1000 || 0.016, 0.05);
        last = t;
        ctx.clearRect(0, 0, w, h);
        for (const p of parts) {
          p.y -= p.vy * dt; p.x += p.vx * dt;
          if (p.y < -4) { p.y = h + 4; p.x = Math.random() * w; }
          const a = 0.16 + 0.5 * (0.5 + 0.5 * Math.sin(t / 1000 * p.sp + p.ph));
          ctx.beginPath();
          ctx.arc(p.x, p.y, p.r, 0, 6.283);
          ctx.fillStyle = "rgba(158,247,203," + a.toFixed(3) + ")";
          ctx.fill();
        }
        raf = requestAnimationFrame(frame);
      };
      const pump = () => { if (!raf && vis && !document.hidden) raf = requestAnimationFrame(frame); };
      if ("IntersectionObserver" in window) {
        new IntersectionObserver((rows) => {
          for (const r of rows) vis = r.isIntersecting;
          pump();
        }, { threshold: 0.02 }).observe(hero);
      }
      addEventListener("visibilitychange", pump);
      raf = requestAnimationFrame(frame);
    }
  }
})();
