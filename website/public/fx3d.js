/* v1.1.62 · 3D scroll pass — parallax, pointer tilt, scroll pops, coverflow gallery.
   Purely additive: with JS off or prefers-reduced-motion the page behaves exactly as before. */
(() => {
  "use strict";
  if (matchMedia("(prefers-reduced-motion: reduce)").matches) return;
  const root = document.documentElement;
  root.classList.add("fx3d");

  /* ── 1 · scroll parallax for [data-par="speed"] ─────────────────── */
  const pars = [...document.querySelectorAll("[data-par]")].map((el) => ({
    el, s: parseFloat(el.dataset.par) || 0.15,
  }));
  let tick = false;
  const applyPar = () => {
    tick = false;
    const mid = innerHeight / 2;
    for (const p of pars) {
      const r = p.el.getBoundingClientRect();
      if (r.bottom < -280 || r.top > innerHeight + 280) continue;
      const y = ((r.top + r.height / 2 - mid) * p.s).toFixed(1);
      p.el.style.transform = `translate3d(0,${y}px,0)`;
    }
  };
  const queuePar = () => { if (!tick) { tick = true; requestAnimationFrame(applyPar); } };
  addEventListener("scroll", queuePar, { passive: true });
  addEventListener("resize", queuePar);
  queuePar();

  /* ── 2 · pointer tilt (fine pointers only; existing hover CSS stays the rest state) */
  if (matchMedia("(pointer:fine)").matches) {
    document.querySelectorAll("[data-tilt]").forEach((el) => {
      el.classList.add("tilt");
      const MAX = 6.5;
      el.addEventListener("pointermove", (e) => {
        const r = el.getBoundingClientRect();
        const x = (e.clientX - r.left) / r.width - 0.5;
        const y = (e.clientY - r.top) / r.height - 0.5;
        el.style.transform =
          `perspective(950px) rotateX(${(-y * MAX).toFixed(2)}deg) rotateY(${(x * MAX).toFixed(2)}deg) translateY(-8px) scale(1.015)`;
        el.style.setProperty("--gx", ((x + 0.5) * 100).toFixed(1) + "%");
        el.style.setProperty("--gy", ((y + 0.5) * 100).toFixed(1) + "%");
      });
      el.addEventListener("pointerleave", () => { el.style.transform = ""; });
    });
  }

  /* ── 3 · one-shot 3D pop for headings / bands / first-reveals ───── */
  const popIO = new IntersectionObserver((es) => {
    for (const e of es) {
      if (!e.isIntersecting) continue;
      e.target.classList.add("fx-pop");
      popIO.unobserve(e.target);
      e.target.addEventListener("animationend", () => e.target.classList.remove("fx-pop"), { once: true });
    }
  }, { threshold: 0.25 });
  document.querySelectorAll(".sec-title, .step, .rider-band, .fx-gallery, .plan:not(.popular)")
    .forEach((el) => popIO.observe(el));

  /* ── 4 · coverflow gallery (scroll-linked 3D + gentle auto tour) ── */
  const track = document.querySelector(".fx-track");
  if (track) {
    const slides = [...track.children].filter((c) => c.classList.contains("fx-slide"));
    let raf = 0;
    const upd = () => {
      raf = 0;
      const c = track.getBoundingClientRect().left + track.clientWidth / 2;
      const half = track.clientWidth * 0.55;
      for (const s of slides) {
        const r = s.getBoundingClientRect();
        let k = (r.left + r.width / 2 - c) / half;
        k = Math.max(-1.6, Math.min(1.6, k));
        const az = Math.min(1, Math.abs(k));
        s.style.transform =
          `translateZ(${(-150 * az).toFixed(0)}px) rotateY(${(-18 * k).toFixed(1)}deg) scale(${(1 - 0.08 * az).toFixed(3)})`;
        s.style.opacity = (1 - 0.38 * az).toFixed(3);
        s.style.filter = `brightness(${(1 - 0.25 * az).toFixed(2)})`;
      }
    };
    const q = () => { if (!raf) raf = requestAnimationFrame(upd); };
    track.addEventListener("scroll", q, { passive: true });
    addEventListener("resize", q);
    const center = () => {
      const s = slides[2] || slides[0];
      if (!s) return;
      track.scrollLeft = s.offsetLeft - (track.clientWidth - s.clientWidth) / 2;
      q();
    };
    center();
    addEventListener("load", center);

    let timer = 0, paused = false;
    const step = () => {
      if (paused || !slides.length) return;
      const w = slides[0].getBoundingClientRect().width + 22;
      const atEnd = track.scrollLeft >= track.scrollWidth - track.clientWidth - 12;
      if (atEnd) track.scrollTo({ left: 0, behavior: "smooth" });
      else track.scrollBy({ left: w, behavior: "smooth" });
      timer = setTimeout(step, 4200);
    };
    const start = () => { clearTimeout(timer); timer = setTimeout(step, 5200); };
    const stop = () => { paused = true; clearTimeout(timer); };
    const resume = () => { paused = false; start(); };
    track.addEventListener("pointerenter", stop);
    track.addEventListener("pointerleave", resume);
    track.addEventListener("touchstart", stop, { passive: true });
    track.addEventListener("focusin", stop);
    start();
  }

  /* ═══ v1.1.62 · Web-G layer: cursor, magnets, grain, coin intro ═══ */

  /* ── 5 · custom cursor (dot + trailing ring, grows over interactive) ── */
  if (matchMedia("(pointer:fine)").matches) {
    const dot = document.createElement("div"); dot.id = "cur-dot";
    const ring = document.createElement("div"); ring.id = "cur-ring";
    document.body.append(dot, ring);
    document.body.classList.add("cursor-fx");
    let x = innerWidth / 2, y = innerHeight / 2, rx = x, ry = y, shown = false;
    addEventListener("pointermove", (e) => {
      x = e.clientX; y = e.clientY;
      if (!shown) { shown = true; }
      dot.style.transform = `translate(${x - 3.5}px,${y - 3.5}px)`;
      const hot = e.target.closest("a, button, input, select, summary, .plan, .card, .fx-slide, .entry");
      document.body.classList.toggle("cursor-hover", !!hot);
    }, { passive: true });
    (function rl() {
      rx += (x - rx) * .17; ry += (y - ry) * .17;
      const r = document.body.classList.contains("cursor-hover") ? 31 : 15;
      ring.style.transform = `translate(${rx - r}px,${ry - r}px)`;
      requestAnimationFrame(rl);
    })();
    document.addEventListener("pointerdown", () => { dot.style.opacity = ".4"; });
    document.addEventListener("pointerup", () => { dot.style.opacity = "1"; });
  }

  /* ── 6 · magnetic buttons ─────────────────────────────────────────── */
  if (matchMedia("(pointer:fine)").matches) {
    document.querySelectorAll(".btn").forEach((b) => {
      b.addEventListener("pointermove", (e) => {
        const r = b.getBoundingClientRect();
        const x = e.clientX - r.left - r.width / 2;
        const y = e.clientY - r.top - r.height / 2;
        b.style.transition = "transform .08s linear";
        b.style.transform = `translate(${(x * .2).toFixed(1)}px,${(y * .3).toFixed(1)}px)`;
      });
      b.addEventListener("pointerleave", () => {
        b.style.transition = "transform .5s cubic-bezier(.2,.8,.3,1.1)";
        b.style.transform = "";
      });
    });
  }

  /* ── 7 · film grain ───────────────────────────────────────────────── */
  {
    const g = document.createElement("div"); g.id = "grain"; g.setAttribute("aria-hidden", "true");
    g.style.backgroundImage = "url(\"data:image/svg+xml," + encodeURIComponent(
      '<svg xmlns="http://www.w3.org/2000/svg" width="260" height="260"><filter id="n"><feTurbulence type="fractalNoise" baseFrequency="0.85" numOctaves="2" stitchTiles="stitch"/></filter><rect width="100%" height="100%" filter="url(#n)"/></svg>'
    ) + "\")";
    document.body.prepend(g);
  }

  /* ── 8 · "INSERT COIN" preloader — once per session, hard failsafe ── */
  {
    let done = false;
    try {
      if (!sessionStorage.getItem("of-coin")) {
        const ov = document.createElement("div"); ov.id = "coin";
        ov.innerHTML = '<b>INSERT COIN<span class="boltmark">⚡</span><em id="coinpct">00</em></b><span class="coinbar" id="coinbar"></span>';
        document.body.prepend(ov);
        const pct = ov.querySelector("#coinpct"), bar = ov.querySelector("#coinbar");
        let n = 0;
        const finish = () => {
          if (done) return; done = true;
          clearInterval(iv);
          ov.style.opacity = 0; ov.style.visibility = "hidden";
          setTimeout(() => ov.remove(), 620);
          try { sessionStorage.setItem("of-coin", "1"); } catch (_) {}
        };
        const iv = setInterval(() => {
          n = Math.min(100, n + 9 + Math.floor(Math.random() * 16));
          pct.textContent = String(n).padStart(2, "0");
          bar.style.width = n + "%";
          if (n >= 100) finish();
        }, 62);
        setTimeout(finish, 2300);
      }
    } catch (_) { if (!done) { const o = document.getElementById("coin"); if (o) o.remove(); } }
  }
})();