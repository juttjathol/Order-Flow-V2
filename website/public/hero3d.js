/* v1.1.62 · WebGL hero vortex (Three.js r128 UMD from CDN) — Web-G style.
   Fails silent: no THREE, no WebGL, small screen, touch-first or reduced-motion
   all leave the existing static hero untouched. */
(() => {
  "use strict";
  if (typeof THREE === "undefined") return;
  if (matchMedia("(prefers-reduced-motion: reduce)").matches) return;
  const hero = document.querySelector(".hero");
  if (!hero || innerWidth < 720) return;
  let renderer;
  try {
    renderer = new THREE.WebGLRenderer({ alpha: true, antialias: false, powerPreference: "low-power" });
  } catch (e) { return; }
  renderer.setPixelRatio(Math.min(devicePixelRatio || 1, 1.6));

  const cv = renderer.domElement;
  cv.id = "gl3d";
  cv.setAttribute("aria-hidden", "true");
  hero.insertBefore(cv, hero.firstChild);

  const scene = new THREE.Scene();
  const cam = new THREE.PerspectiveCamera(56, 1, 1, 500);
  cam.position.z = 96;

  const C1 = new THREE.Color("#3ddc97"), C2 = new THREE.Color("#e8c36a"), C3 = new THREE.Color("#7dffc4");
  const mk = (N, r0, r1, size, op) => {
    const pos = new Float32Array(N * 3), col = new Float32Array(N * 3);
    for (let i = 0; i < N; i++) {
      const a = Math.random() * Math.PI * 2;
      const t = Math.pow(Math.random(), .7);
      const r = r0 + (r1 - r0) * t + Math.sin(a * 3 + t * 4) * 4.2;
      pos[i*3]   = Math.cos(a) * r;
      pos[i*3+1] = Math.sin(a) * r * .58 + (t - .5) * 16;
      pos[i*3+2] = (Math.random() - .5) * 46 + Math.sin(a * 2) * 5;
      const mix = Math.min(1, Math.max(0, 1 - (r - r0) / (r1 - r0 + .001) + (Math.random() - .5) * .5));
      const c = C1.clone().lerp(Math.random() < .18 ? C2 : C3, mix);
      col[i*3] = c.r; col[i*3+1] = c.g; col[i*3+2] = c.b;
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute("position", new THREE.BufferAttribute(pos, 3));
    g.setAttribute("color", new THREE.BufferAttribute(col, 3));
    return new THREE.Points(g, new THREE.PointsMaterial({
      size, vertexColors: true, transparent: true, opacity: op,
      depthWrite: false, blending: THREE.AdditiveBlending,
    }));
  };
  const ring = mk(3400, 30, 66, 1.25, .85);
  const far  = mk(900, 78, 150, .8, .34);
  ring.rotation.x = .30; far.rotation.x = .24;
  scene.add(ring, far);

  const torus = new THREE.Mesh(
    new THREE.TorusGeometry(52, .16, 6, 96),
    new THREE.MeshBasicMaterial({ color: 0x3ddc97, transparent: true, opacity: .20 })
  );
  torus.rotation.x = 1.18; scene.add(torus);

  let mx = 0, my = 0, tx = 0, ty = 0, sc = 0, vis = true, raf = 0;
  addEventListener("pointermove", (e) => {
    tx = (e.clientX / innerWidth - .5) * 2;
    ty = (e.clientY / innerHeight - .5) * 2;
  }, { passive: true });
  addEventListener("scroll", () => { sc = scrollY / Math.max(320, hero.offsetHeight); }, { passive: true });

  const fit = () => {
    const r = hero.getBoundingClientRect();
    renderer.setSize(Math.max(2, r.width), Math.max(2, r.height), false);
    cam.aspect = r.width / Math.max(1, r.height);
    cam.updateProjectionMatrix();
    cv.style.opacity = "1";
  };
  addEventListener("resize", fit);

  const clock = new THREE.Clock();
  const loop = () => {
    raf = requestAnimationFrame(loop);
    if (!vis) return;
    const t = clock.getElapsedTime();
    mx += (tx - mx) * .045; my += (ty - my) * .045;
    ring.rotation.z = t * .05 + mx * .18;
    ring.rotation.y = Math.sin(t * .12) * .10 + mx * .10;
    far.rotation.z  = -t * .017;
    torus.rotation.z = -t * .07 + mx * .12;
    torus.rotation.x = 1.18 + my * .16;
    cam.position.x = mx * 7;
    cam.position.y = -my * 4 - sc * 26;
    cam.lookAt(0, -sc * 30, 0);
    const fade = Math.max(0, 1 - sc * 1.35);
    ring.material.opacity = .85 * fade;
    far.material.opacity = .34 * fade;
    torus.material.opacity = .2 * fade;
    renderer.render(scene, cam);
  };
  new IntersectionObserver((es) => { vis = es[0].isIntersecting; }, { threshold: 0 }).observe(hero);
  fit(); loop();
})();
