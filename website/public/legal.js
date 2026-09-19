// Legal-pages support: year stamps + the cookie-choice manager on cookies.html.
// Lives in a file (not inline) so the site CSP can keep script-src strict.
(() => {
  const y = String(new Date().getFullYear());
  document.querySelectorAll(".y, #y").forEach((e) => { e.textContent = y; });

  const st = document.getElementById("ck-status");
  const say = (m) => { if (st) st.textContent = m; };
  const yes = document.getElementById("ck-yes");
  const no = document.getElementById("ck-no");
  if (yes) yes.addEventListener("click", () => {
    try {
      localStorage.setItem("of-consent", "yes");
      say("Accepted — the main site may remember your currency view. Reload the home page to see it.");
    } catch (_) {
      say("Storage is blocked in this browser — nothing can be remembered, which is the same as declining. The site works fine either way.");
    }
  });
  if (no) no.addEventListener("click", () => {
    try {
      localStorage.setItem("of-consent", "no");
      localStorage.removeItem("of-ccy");
      sessionStorage.removeItem("of-myr-rates");
      say("Cleared. Prices will stay in RM and nothing optional will be stored on this device.");
    } catch (_) {
      say("Nothing to clear — storage is already blocked, which is a full decline.");
    }
  });
})();
