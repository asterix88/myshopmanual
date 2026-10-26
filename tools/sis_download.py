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
PAUSE_SECONDS = 1.0

# SIS's print button calls window.print(); replace it so no print dialog
# pops up and stops the script.
NO_PRINT_DIALOG = "window.print = () => {};"

COLLECT_LINKS = r"""() => {
  const out = [];
  for (const a of document.querySelectorAll('a[href]')) {
    const href = a.href;
    if (!/#\/(detail|print-preview)/i.test(href)) continue;
    // Book entries (no document number) list documents, they are not one.
    if (/#\/detail/i.test(href) && !/serviceIeSystemControlNumber=/i.test(href)) continue;
    let title = (a.innerText || a.title || a.getAttribute('aria-label') || '').trim();
    // An icon-only link: take the title from the result row around it.
    for (let row = a.parentElement; !title && row && row !== document.body; row = row.parentElement)
      title = (row.innerText || '').trim().split('\n')[0].trim();
    title = title.replace(/\s+/g, ' ');
    out.push([href, title || 'dokumen']);
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

# Turns the ready page into one self-contained HTML document holding only
# the document itself: the SIS menus, tabs, document tree and footer are
# left out. Pictures become data: URLs (they need the SIS login) and
# stylesheets are copied inline.
SNAPSHOT = r"""async ([ie, title]) => {
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
  const JUNK = 'nav, header, footer, button, .d-print-none, [class*=Navigation], ' +
               '[class*=AccordionTree], [class*=Breadcrumb], [class*=breadcrumb], ' +
               '[class*=ookie], [class*=Banner], [class*=banner]';
  // The document part: the smallest block holding both SIS's visible print
  // button (in the document's title bar) and the visible "i0..." number.
  const visible = el => !!(el && el.getClientRects().length);
  const button = [...document.querySelectorAll(
      "button._CommonPrintButton, button[title*='print' i]")].find(visible);
  let number = null;
  if (ie) {
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    let node;
    while ((node = walker.nextNode())) {
      if (node.nodeValue.trim() === ie && visible(node.parentElement)) {
        number = node.parentElement;
        break;
      }
    }
  }
  let part = null;
  if (button && number) {
    const above = new Set();
    for (let el = button; el; el = el.parentElement) above.add(el);
    part = number;
    while (part && !above.has(part)) part = part.parentElement;
    if (part === document.body || part === document.documentElement) part = null;
  }
  const source = part || document.body;
  const content = source.cloneNode(true);
  const live = [...source.querySelectorAll('img')];
  const copies = [...content.querySelectorAll('img')];
  for (let i = 0; i < copies.length; i++) {
    const src = live[i] && (live[i].currentSrc || live[i].src);
    copies[i].removeAttribute('srcset');
    copies[i].removeAttribute('loading');
    if (!src || src.startsWith('data:')) continue;
    try { copies[i].src = await toDataUrl(src); } catch (e) { copies[i].src = src; }
  }
  content.querySelectorAll(JUNK).forEach(n => n.remove());
  content.querySelectorAll('script, link, style').forEach(n => n.remove());

  let css = '';
  for (const sheet of document.styleSheets) {
    try { for (const rule of sheet.cssRules) css += rule.cssText + '\n'; } catch (e) {}
  }
  const doc = document.implementation.createHTMLDocument(title);
  const meta = doc.createElement('meta');
  meta.setAttribute('charset', 'utf-8');
  doc.head.appendChild(meta);
  const base = doc.createElement('base');
  base.href = location.origin + '/';
  doc.head.appendChild(base);
  const style = doc.createElement('style');
  style.textContent = css + '\nbody { margin: 0; background: #fff; }';
  doc.head.appendChild(style);
  // SIS's title bar may sit outside the document part: keep the title.
  if (!(content.innerText || content.textContent).toLowerCase().includes(title.toLowerCase())) {
    const h = doc.createElement('h2');
    h.textContent = title;
    doc.body.appendChild(h);
  }
  doc.body.appendChild(doc.importNode(content, true));
  return [(content.textContent || '').trim().length, !!part,
          '<!doctype html>' + doc.documentElement.outerHTML];
}"""

# SIS 2.0 has one print button per tab (Service, Repair, ...); only the one
# on the open tab is visible.
PRINT_BUTTON = (
    "button._CommonPrintButton:visible, "
    "button[title*='print' i]:visible, [aria-label*='print' i]:visible"
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


PAGE_PROBE = TOOLS / "sis-probe-halaman.html"


def write_page_probe(page) -> None:
    """Saves the page's HTML (pictures left out) for the developer."""
    try:
        html = page.evaluate("""() => {
          const d = document.documentElement.cloneNode(true);
          d.querySelectorAll('script, style, svg').forEach(n => n.remove());
          d.querySelectorAll('img').forEach(i => i.removeAttribute('src'));
          return d.outerHTML;
        }""")
        PAGE_PROBE.write_text(html, encoding="utf-8")
        say(f"  Halaman disimpan di {PAGE_PROBE}. Kirim file itu ke Claude.")
    except Error:
        pass


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


# Pictures still missing: every "Illustration N" caption needs a loaded <img>.
MISSING_PICTURES = r"""() => {
  const text = document.body ? document.body.innerText : '';
  const captions = new Set(text.match(/Illustration\s+\d+/g) || []).size;
  const loaded = [...document.images].filter(i => i.complete && i.naturalWidth > 1 &&
                                               i.naturalWidth * i.naturalHeight > 2500).length;
  const loading = [...document.images].filter(i => !i.complete).length;
  return Math.max(captions - loaded, 0) + loading;
}"""


def skip_pressed() -> bool:
    """True when S was pressed in the console window (Windows only)."""
    try:
        import msvcrt
    except ImportError:
        return False
    hit = False
    while msvcrt.kbhit():
        hit = msvcrt.getwch().lower() == "s" or hit
    return hit


def wait_for_print_view(view) -> int:
    """Waits, without a time limit, until the print view's text stops changing
    and every picture has loaded (SIS's print() call alone is not trusted).
    Pressing S saves the document as it is; returns the pictures still
    missing then."""
    start = time.time()
    next_note = start + 60
    last, same, missing = -1, 0, 0
    while True:
        try:
            # Lazy pictures below the window would never load on their own.
            view.evaluate("document.querySelectorAll('img[loading=lazy]')"
                          ".forEach(i => { i.loading = 'eager'; })")
            size = view.evaluate(PAGE_SIZE)
            missing = view.evaluate(MISSING_PICTURES)
        except Error:
            size, missing = -1, 1
        same = same + 1 if size == last and size > 200 and missing == 0 else 0
        if same >= 3:
            return 0
        if time.time() >= next_note:
            say(f"  Masih menunggu {missing} gambar ({time.time() - start:.0f} dtk)... "
                "tekan S untuk simpan apa adanya.")
            next_note += 60
        if skip_pressed():
            return missing
        last = size
        time.sleep(0.5)


def open_print_view(context, page, timeout_ms: int):
    """Clicks SIS's print button, which readies the document for printing,
    then waits for it on the document tab itself. The preview tab SIS may
    open is not used (save_document closes it). Returns None when there is
    no print button."""
    try:
        button = page.locator(PRINT_BUTTON).first
        button.wait_for(state="visible", timeout=timeout_ms)
    except TimeoutError:
        return None
    button.click()
    time.sleep(0.8)
    missing = wait_for_print_view(page)
    if missing:
        say(f"  Peringatan: {missing} gambar belum termuat, disimpan apa adanya.")
    return page


def save_document(context, page, renderer, href: str, title: str, target: Path) -> bool:
    """Opens the document in the tab the user logged in with (SIS may keep
    its login per tab), so that tab is reused rather than closed."""
    view = None
    try:
        t0 = time.time()
        # SIS shows the document's "i0..." number once it has loaded it, so
        # the app can stay open between documents (much faster than a
        # reload). Without that number, reload so the old print button goes.
        ie = re.search(r"serviceIeSystemControlNumber=(i\d+)", href)
        if ie:
            page.goto(href, wait_until="commit", timeout=60000)
            page.wait_for_function(
                "n => document.body && document.body.innerText.includes(n)",
                arg=ie.group(1), timeout=60000)
        else:
            page.goto("about:blank")
            page.goto(href, wait_until="domcontentloaded", timeout=60000)
        t1 = time.time()
        view = open_print_view(context, page, 40000)
        t2 = time.time()
        if view is None:
            # The full app page (menus, tree) is no use as a manual page.
            say("  Tombol print tidak ketemu, dokumen ini dilewati.")
            write_probe(page)
            return False
        size, found_part, html = view.evaluate(SNAPSHOT, [ie.group(1) if ie else "", title])
        if not found_part or size < 200:
            say("  Isi dokumen tidak ketemu, dokumen ini dilewati.")
            write_page_probe(view)
            return False
    except Error as e:
        say(f"  Gagal membuka: {e.message.splitlines()[0]}")
        write_probe(page)
        return False
    finally:
        # SIS's print button opens a print preview tab (sometimes only after
        # a moment); close every tab but the working one so none pile up.
        for pg in context.pages:
            if pg is not page:
                try:
                    pg.close()
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
    say(f"  buka {t1 - t0:.0f} dtk, print {t2 - t1:.0f} dtk, simpan {time.time() - t2:.0f} dtk")
    return True


def sis_tab(context):
    """The last open tab showing SIS (the one the user is looking at)."""
    tabs = [pg for pg in context.pages if "cat.com" in pg.url]
    return (tabs or context.pages)[-1]


# Scrolls every scrollable box to the bottom, so results drawn only when
# they come into view are in the page too.
SCROLL_ALL = """() => {
  window.scrollTo(0, document.body.scrollHeight);
  for (const el of document.querySelectorAll('*'))
    if (el.scrollHeight > el.clientHeight + 20) el.scrollTop = el.scrollHeight;
}"""

LIST_PROBE = TOOLS / "sis-probe-daftar.txt"


def collect(page, found: dict) -> tuple[int, int]:
    """Adds the page's document links; returns (documents on page, new ones).
    Writes them all to sis-probe-daftar.txt for checking."""
    for _ in range(4):
        for frame in page.frames:
            try:
                frame.evaluate(SCROLL_ALL)
            except Error:
                pass
        time.sleep(0.5)
    links = []
    for frame in page.frames:
        try:
            links += frame.evaluate(COLLECT_LINKS)
        except Error:
            pass
    on_page: dict[str, str] = {}
    for href, title in links:
        on_page.setdefault(href, title)
    added = 0
    rows = []
    for href, title in on_page.items():
        new = href not in found
        rows.append(("BARU  " if new else "SUDAH ") + title + "  " + href)
        if new:
            found[href] = title
            added += 1
    with LIST_PROBE.open("a", encoding="utf-8") as f:
        f.write(f"=== {page.url}\n" + "\n".join(rows) + "\n\n")
    return len(on_page), added


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
        LIST_PROBE.unlink(missing_ok=True)
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
            say(f"  Di halaman ini {on_page} dokumen: {added} baru, "
                f"{on_page - added} sudah diambil sebelumnya. Total {len(found)}.")
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
