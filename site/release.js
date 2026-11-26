// The Copy button, and the newest release's version, download size and date under it.
// The install command itself never changes (it always follows the latest release), so the page works
// as it is if GitHub can't be reached.
(() => {
  const button = document.getElementById("copy");
  const label = document.getElementById("copy-label");
  const command = document.getElementById("command").textContent.trim();
  let timer;
  button.addEventListener("click", async () => {
    try {
      await navigator.clipboard.writeText(command);
      label.textContent = "Copied";
    } catch (e) {
      // no clipboard access: select the command so it can be copied by hand
      const range = document.createRange();
      range.selectNodeContents(document.getElementById("command"));
      const sel = window.getSelection();
      sel.removeAllRanges();
      sel.addRange(range);
      label.textContent = "Press ⌘C";
    }
    clearTimeout(timer);
    timer = setTimeout(() => { label.textContent = "Copy"; }, 2500);
  });
})();

(async () => {
  const meta = document.getElementById("release-meta");
  try {
    const res = await fetch("https://api.github.com/repos/goseahawk/kirki/releases/latest",
                            { headers: { Accept: "application/vnd.github+json" } });
    if (!res.ok) return;
    const release = await res.json();
    const zip = (release.assets || []).find((a) => /-asahi\.zip$/.test(a.name));
    if (!zip) return;
    const size = (zip.size / 1024 ** 3).toFixed(1).replace(/\.0$/, "");
    const date = new Date(release.published_at).toLocaleDateString(undefined,
                   { day: "numeric", month: "long", year: "numeric" });
    meta.textContent = `kirki ${release.tag_name} · ${size} GB download · released ${date} · for M1 and M2 Macs`;
  } catch (e) {
    // offline or rate-limited: keep the plain description
  }
})();
