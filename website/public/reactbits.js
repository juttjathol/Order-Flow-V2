/* v1.1.63 site · React Bits pack — vanilla recreations of the signature
   reactbits.dev animations (DecryptedText, BlurText, SpotlightCard,
   GlareHover, BorderGlow). Purely additive: every style hangs off html.rbits
   which only exists when this script runs; with JS off or
   prefers-reduced-motion the page is byte-for-byte the old experience. */
(() => {
  "use strict";
  if (matchMedia("(prefers-reduced-motion: reduce)").matches) return;
  const root = document.documentElement;
  root.classList.add("rbits");
  const fine = matchMedia("(pointer:fine)").matches;

  /* ── 1 · DecryptedText — hero title, then the download heading ───── */
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
      const spans = [];
      for (const ch of tn.textContent) {
        const s = document.createElement("span");
        s.className = "rb-ch";
        s.textContent = ch;
        frag.appendChild(s);
        if (ch.trim()) spans.push(s);
        s.setAttribute("aria-hidden", "false");
      }
      tn.parentNode.replaceChild(frag, tn);
      for (const s of spans) {
        const orig = s.textContent;
        const startAt = (i++) * 22;
        setTimeout(() => {
          s.classList.add("rb-s");
          const dur = 240 + Math.floor(Math.random() * 260);
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
  if (heroH1) requestAnimationFrame(() => setTimeout(() => decrypt(heroH1), 450));
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

  /* ── 2 · BlurText — section titles land word-by-word out of the blur ─ */
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

  /* ── 3 · SpotlightCard — mint light pools under the pointer on cards ── */
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

  /* ── 4 · GlareHover CSS does the hover sweep; we add one auto-ping ────
      on the hero CTAs after load and on the download button when seen. */
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

  /* ── 5 · BorderGlow — light beam orbits the download band ─────────── */
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
})();
