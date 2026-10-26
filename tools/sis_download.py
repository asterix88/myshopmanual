"""Save Caterpillar SIS 2.0 documents as PDFs with a real text layer.

Opens Chrome (or Edge) with its own profile kept in tools/.sis-profile, so
the SIS login is remembered between runs. The user logs in, searches and
filters in that window; the script collects the result links page by page,
then opens each document, presses SIS's own print button and saves what SIS
would print as a PDF (text stays text, unlike "Microsoft Print to PDF").

Files are named "NNN Title.pdf" in the order of the results list, so a later
merge keeps SIS's order. Files that already exist are skipped, so a run that
stops halfway can simply be started again.

    python tools/sis_download.py "source/CAT395/R&I"

When the page layout is not what the script expects it writes
tools/sis-probe.txt (links and buttons on the page) to send to the developer.
"""

import argparse
import re
import sys
import time
from pathlib import Path

from playwright.sync_api import Error, TimeoutError, sync_playwright

SIS_URL = "https://sis2.cat.com/"
TOOLS = Path(__file__).resolve().parent
PROFILE = TOOLS / ".sis-profile"
PROBE = TOOLS / "sis-probe.txt"
# Pause between documents, to go easy on the SIS server.
PAUSE_SECONDS = 2.0

# SIS opens its print view and calls window.print() once the document is
# ready; replace it so no print dialog pops up and the script knows when.
NO_PRINT_DIALOG = "window.print = () => { window.__sisPrinted = true; };"

COLLECT_LINKS = r"""() => {
  const out = [];
  for (const a of document.querySelectorAll('a[href]')) {
    const href = a.href;
    if (!/#\/(detail|print-preview)/i.test(href)) continue;
    const title = (a.innerText || a.title || '').trim().replace(/\s+/g, ' ');
    if (title) out.push([href, title]);
  }
  return out;
}"""

PROBE_PAGE = r"""() => {
  const rows = ['URL ' + location.href, ''];
  for (const a of document.querySelectorAll('a[href]'))
    rows.push('A ' + a.getAttribute('href') + ' | ' + (a.innerText || '').trim().slice(0, 80));
  for (const b of document.querySelectorAll('button, [role=button], [title], [aria-label], mat-icon'))
    rows.push('B ' + b.tagName + ' title=' + (b.title || '') + ' aria=' + (b.getAttribute('aria-label') || '') +
              ' class=' + (b.className && b.className.baseVal === undefined ? b.className : '') +
              ' | ' + (b.innerText || '').trim().slice(0, 40));
  return rows.join('\n');
}"""

# Text length that only changes when the page is still loading.
PAGE_SIZE = "() => document.body ? document.body.innerText.length : 0"

IMAGES_LOADED = """() => [...document.images].every(i => i.complete)"""

# Turns the ready page into one self-contained HTML document: pictures become
# data: URLs (they need the SIS login) and stylesheets are copied inline.
SNAPSHOT = r"""async () => {
  const toDataUrl = async (url) => {
    const r = await fetch(url, {credentials: 'include'});
    const blob = await r.blob();
    return await new Promise((ok, fail) => {
      const fr = new FileReader();
      fr.onload = () => ok(fr.result);
      fr.onerror = fail;
      fr.readAsDataURL(blob);
    });
  };
  const doc = document.documentElement.cloneNode(true);
  const live = [...document.images];
  const copies = [...doc.querySelectorAll('img')];
  for (let i = 0; i < copies.length; i++) {
    const src = live[i] && (live[i].currentSrc || live[i].src);
    copies[i].removeAttribute('srcset');
    copies[i].removeAttribute('loading');
    if (!src || src.startsWith('data:')) continue;
    try { copies[i].src = await toDataUrl(src); } catch (e) { copies[i].src = src; }
  }
  let css = '';
  for (const sheet of document.styleSheets) {
    try { for (const rule of sheet.cssRules) css += rule.cssText + '\n'; } catch (e) {}
  }
  doc.querySelectorAll('script, link[rel=stylesheet], style').forEach(n => n.remove());
  const head = doc.querySelector('head');
  const style = document.createElement('style');
  style.textContent = css;
  head.appendChild(style);
  const base = document.createElement('base');
  base.href = location.origin + '/';
  head.prepend(base);
  const meta = document.createElement('meta');
  meta.setAttribute('charset', 'utf-8');
  head.prepend(meta);
  return '<!doctype html>' + doc.outerHTML;
}"""

PRINT_BUTTON = (
    "[title*='print' i], [aria-label*='print' i], "
    "button:has(mat-icon:text-is('print')), mat-icon:text-is('print')"
)


def say(text: str) -> None:
    print(text, flush=True)


def safe_name(title: str) -> str:
    name = re.sub(r'[<>:"/\\|?*\x00-\x1f]+', " ", title)
    name = re.sub(r"\s+", " ", name).strip(" .")
    return name[:120] or "dokumen"


def write_probe(page) -> None:
    """Dumps the links and buttons of the page and its frames."""
    parts = []
    for frame in page.frames:
        try:
            parts.append(f"=== frame {frame.url}\n" + frame.evaluate(PROBE_PAGE))
        except Error as e:
            parts.append(f"=== frame {frame.url}\nerror: {e.message.splitlines()[0]}")
    PROBE.write_text("\n\n".join(parts), encoding="utf-8")
    say(f"  Detail halaman disimpan di {PROBE}. Kirim file itu ke Claude.")


def launch_browser(p, headless: bool, user_data: Path | None = None):
    """Chrome if installed, otherwise Edge (always there on Windows)."""
    last = None
    for channel in ("chrome", "msedge"):
        try:
            if user_data:
                return p.chromium.launch_persistent_context(
                    str(user_data), channel=channel, headless=headless,
                    no_viewport=True)
            return p.chromium.launch(channel=channel, headless=headless)
        except Error as e:
            last = e
    raise SystemExit(f"Chrome atau Edge tidak bisa dibuka: {last}")


def wait_until_settled(page, timeout: float = 45) -> None:
    """Waits for the text to stop growing and all pictures to finish."""
    end = time.time() + timeout
    last, same = -1, 0
    while time.time() < end:
        try:
            size = page.evaluate(PAGE_SIZE)
            images = page.evaluate(IMAGES_LOADED)
        except Error:
            size, images = -1, False
        same = same + 1 if size == last and size > 200 and images else 0
        if same >= 3:
            return
        last = size
        time.sleep(0.7)


def open_print_view(context, page, timeout_ms: int):
    """Clicks SIS's print button; returns the page that holds the print view,
    or None when there is no print button."""
    try:
        button = page.locator(PRINT_BUTTON).first
        button.wait_for(state="visible", timeout=timeout_ms)
    except TimeoutError:
        return None
    pages_before = set(context.pages)
    button.click()
    time.sleep(1.5)
    new = [pg for pg in context.pages if pg not in pages_before]
    view = new[0] if new else page
    try:
        view.wait_for_function("window.__sisPrinted === true", timeout=60000)
    except TimeoutError:
        pass  # no print() call seen: fall back to waiting for the page
    wait_until_settled(view, 20)
    return view


def save_document(context, page, renderer, href: str, title: str, target: Path) -> bool:
    """Opens the document in the tab the user logged in with (SIS may keep
    its login per tab), so that tab is reused rather than closed."""
    view = None
    try:
        # A full reload, so the previous document's print button is gone.
        page.goto("about:blank")
        page.goto(href, wait_until="domcontentloaded", timeout=60000)
        view = open_print_view(context, page, 40000)
        if view is None:
            say("  Tombol print tidak ketemu, halaman disimpan apa adanya.")
            write_probe(page)
            wait_until_settled(page)
            view = page
        html = view.evaluate(SNAPSHOT)
    except Error as e:
        say(f"  Gagal membuka: {e.message.splitlines()[0]}")
        write_probe(page)
        return False
    finally:
        if view is not None and view is not page:
            try:
                view.close()
            except Error:
                pass
    out = renderer.new_page()
    try:
        out.set_content(html, wait_until="load", timeout=60000)
        out.evaluate("t => { document.title = t; }", title)
        tmp = target.with_suffix(".tmp")
        out.pdf(path=str(tmp), format="A4", print_background=True,
                margin={"top": "12mm", "bottom": "12mm", "left": "10mm", "right": "10mm"})
        tmp.replace(target)
    finally:
        out.close()
    return True


def sis_tab(context):
    """The last open tab showing SIS (the one the user is looking at)."""
    tabs = [pg for pg in context.pages if "cat.com" in pg.url]
    return (tabs or context.pages)[-1]


def collect(page, found: dict) -> tuple[int, int]:
    """Adds the page's document links; returns (links on page, new ones)."""
    links = []
    for frame in page.frames:
        try:
            links += frame.evaluate(COLLECT_LINKS)
        except Error:
            pass
    added = 0
    for href, title in links:
        if href not in found:
            found[href] = title
            added += 1
    return len(links), added


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("folder", type=Path, help="folder tujuan, mis. source/CAT395/R&I")
    args = ap.parse_args()
    args.folder.mkdir(parents=True, exist_ok=True)

    with sync_playwright() as p:
        context = launch_browser(p, headless=False, user_data=PROFILE)
        context.add_init_script(NO_PRINT_DIALOG)
        page = context.pages[0] if context.pages else context.new_page()
        page.goto(SIS_URL)

        say("")
        say("1. Di jendela Chrome yang terbuka: login SIS (sekali saja, nanti diingat).")
        say("2. Cari dan pasang filter (mis. 395 + Disassembly and Assembly).")
        say("3. Saat daftar hasil tampil, kembali ke jendela hitam ini.")
        found: dict[str, str] = {}
        while True:
            say("")
            cmd = input("Enter = ambil daftar di halaman ini | m = mulai download | q = batal: ")
            cmd = cmd.strip().lower()
            if cmd == "q":
                context.close()
                return 0
            current = sis_tab(context)
            if cmd == "m" and found:
                work = current
                break
            on_page, added = collect(current, found)
            say(f"  +{added} dokumen baru, total {len(found)}.")
            if on_page == 0:
                say("  Tidak ada link dokumen di halaman ini.")
                write_probe(current)
            elif added == 0:
                say("  Semua dokumen di halaman ini sudah diambil sebelumnya.")
            elif cmd == "m":
                work = current
                break
            else:
                say("  Kalau hasilnya lebih dari satu halaman, pindah ke halaman berikutnya lalu Enter lagi.")

        if not found:
            say("Belum ada dokumen yang diambil.")
            context.close()
            return 1

        renderer = launch_browser(p, headless=True)
        done = skipped = failed = 0
        total = len(found)
        for n, (href, title) in enumerate(found.items(), 1):
            target = args.folder / f"{n:03d} {safe_name(title)}.pdf"
            if target.exists():
                skipped += 1
                continue
            say(f"[{n}/{total}] {title}")
            if save_document(context, work, renderer, href, title, target):
                done += 1
            else:
                failed += 1
            time.sleep(PAUSE_SECONDS)
        renderer.close()
        context.close()

    say("")
    say(f"Selesai: {done} disimpan, {skipped} sudah ada, {failed} gagal.")
    say(f"Folder: {args.folder.resolve()}")
    if failed:
        say("Jalankan lagi untuk mencoba yang gagal (yang sudah ada dilewati).")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
