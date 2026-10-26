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
    // Results of the previous page SIS still keeps, hidden, are not taken.
    if (!a.getClientRects().length) continue;
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
  // SIS's own print view (sometimes opened in this tab) wraps exactly the
  // document, title bar included.
  const printContent = [...document.querySelectorAll('._ServiceDetailPrintContent')].filter(visible);
  if (printContent.length) part = printContent[printContent.length - 1];
  else if (button && number) {
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
                    no_viewport=True, ignore_default_args=["--no-sandbox"])
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


def page_links(page) -> list[tuple[str, str]]:
    links = []
    for frame in page.frames:
        try:
            links += frame.evaluate(COLLECT_LINKS)
        except Error:
            pass
    on_page: dict[str, str] = {}
    for href, title in links:
        on_page.setdefault(href, title)  # title link + icon link: once
    return list(on_page.items())


def collect(page, found: list, page_no: int) -> int:
    """Adds every document on the results page (also one already taken from
    another page: Anas wants them all); returns how many. Waits until the
    list stops changing, so a page still being drawn is not half taken.
    Writes them all to sis-probe-daftar.txt for checking."""
    links, end = [], time.time() + 15
    while time.time() < end:
        for frame in page.frames:
            try:
                frame.evaluate(SCROLL_ALL)
            except Error:
                pass
        time.sleep(1.0)
        now = page_links(page)
        if now and now == links:
            break
        links = now
    earlier = {href: n for n, (href, _, _) in enumerate(found, 1)}
    rows = []
    for href, title in links:
        if href in earlier:
            say(f"    link sama dengan dokumen ke-{earlier[href]}: {title} (tetap diunduh)")
        found.append((href, title, page_no))
        rows.append(f"{len(found):03d} {title}  {href}")
    with LIST_PROBE.open("a", encoding="utf-8") as f:
        f.write(f"=== halaman hasil ke-{page_no} {page.url}\n" + "\n".join(rows) + "\n\n")
    return len(links)


class SessionDenied(Exception):
    """SIS refused the login: too many sessions open for the account."""


def check_session(page) -> None:
    if "sessiondenied" in page.url.lower():
        raise SessionDenied


LOGOUT_CLICK = r"""() => {
  const visible = el => !!el.getClientRects().length;
  const isLogout = el => visible(el) &&
      /^(log\s*out|sign\s*out|logoff|keluar)$/i.test((el.innerText || '').trim());
  // Links and buttons first: a wrapping <div> with the same text is no button.
  const pick = () =>
      [...document.querySelectorAll('a, button, [role=menuitem]')].find(isLogout) ||
      [...document.querySelectorAll('li, span, div')].find(isLogout);
  let el = pick();
  if (!el) {
    // The logout entry may sit in a closed account or main menu: open them.
    const menus = [...document.querySelectorAll(
        "[aria-label*='account' i], [aria-label*='profile' i], [aria-label*='user' i], " +
        "[title*='account' i], [title*='profile' i], [class*='avatar' i], [class*='Profile'], " +
        "[class*='UserMenu'], [class*='user-menu'], .navbar-toggler, [class*='Hamburger']")]
        .filter(visible);
    for (const m of menus) {
      m.click();
      el = pick();
      if (el) break;
    }
  }
  if (!el) return false;
  el.click();
  return true;
}"""


def logout(context) -> None:
    """Logs out of SIS so the session does not stay open on SIS's side."""
    if not context.pages:
        return
    page = sis_tab(context)
    clicked = False
    for _ in range(2):
        try:
            clicked = page.evaluate(LOGOUT_CLICK)
        except Error:
            clicked = False
        if clicked:
            break
        time.sleep(1.5)  # a menu that opened may need a moment
    if clicked:
        time.sleep(4)
        say("Logout SIS selesai.")
        return
    say("Tombol logout SIS tidak ketemu. Klik logout sendiri di jendela Chrome,")
    try:
        input("lalu tekan Enter di sini untuk menutup Chrome: ")
    except (EOFError, KeyboardInterrupt):
        pass


def download_folder(p, context, folder: Path) -> bool:
    """Collects the results pages and saves their documents into folder.
    Returns False when the user quits."""
    folder.mkdir(parents=True, exist_ok=True)
    say("")
    say(f"Folder tujuan: {folder}")
    say("Di jendela Chrome: cari dan pasang filter (mis. 395 + Disassembly and Assembly).")
    say("Saat daftar hasil tampil, kembali ke jendela hitam ini.")
    found: list[tuple[str, str, int]] = []
    pages_taken = 0
    last_page: list[str] = []
    LIST_PROBE.unlink(missing_ok=True)
    while True:
        say("")
        cmd = input("Enter = ambil daftar di halaman ini | m = mulai download | q = keluar: ")
        cmd = cmd.strip().lower()
        if cmd == "q":
            return False
        current = sis_tab(context)
        check_session(current)
        # m on the results page just taken starts at once; on a new
        # results page, that page is taken first.
        if cmd == "m" and found and [h for h, _ in page_links(current)] == last_page:
            work = current
            break
        pages_taken += 1
        on_page = collect(current, found, pages_taken)
        last_page = [h for h, _, _ in found[len(found) - on_page:]]
        say(f"  Halaman hasil ke-{pages_taken}: {on_page} dokumen. Total {len(found)}.")
        if on_page == 0:
            pages_taken -= 1
            say("  Tidak ada link dokumen di halaman ini.")
            write_probe(current)
        elif cmd == "m":
            work = current
            break
        else:
            say("  Kalau hasilnya lebih dari satu halaman, pindah ke halaman berikutnya lalu Enter lagi.")

    renderer = launch_browser(p, headless=True)
    done = skipped = failed = 0
    total = len(found)
    saved = {re.sub(r"^\d+ ", "", f.stem).lower() for f in folder.glob("*.pdf")}
    title_count: dict[str, int] = {}
    for _, title, _ in found:
        key = safe_name(title).lower()
        title_count[key] = title_count.get(key, 0) + 1
    try:
        for n, (href, title, _) in enumerate(found, 1):
            target = folder / f"{n:03d} {safe_name(title)}.pdf"
            # Already saved. A title that is unique in the list also counts
            # under another number (the list order can change between runs).
            key = safe_name(title).lower()
            if target.exists() or (title_count[key] == 1 and key in saved):
                skipped += 1
                continue
            say(f"[{n}/{total}] {title}")
            if save_document(context, work, renderer, href, title, target):
                done += 1
            else:
                failed += 1
            check_session(work)
            time.sleep(PAUSE_SECONDS)
    finally:
        renderer.close()

    say("")
    say(f"Selesai: {done} disimpan, {skipped} sudah ada, {failed} gagal.")
    say(f"Folder: {folder.resolve()}")
    if failed:
        say("Yang gagal bisa dicoba lagi nanti (yang sudah ada dilewati).")
    return True


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("folder", type=Path, help="folder tujuan, mis. source/CAT395/R&I")
    args = ap.parse_args()
    # Later folders are asked for relative to the same root (source\).
    root = Path(args.folder.parts[0]) if len(args.folder.parts) > 1 else Path(".")

    with sync_playwright() as p:
        context = launch_browser(p, headless=False, user_data=PROFILE)
        context.add_init_script(NO_PRINT_DIALOG)
        page = context.pages[0] if context.pages else context.new_page()
        page.goto(SIS_URL)
        say("")
        say("Login SIS di jendela Chrome yang terbuka (kalau diminta).")
        say("Satu jendela ini dipakai untuk semua folder, jadi tidak perlu login ulang.")
        say("Selesai atau batal: ketik q (atau Ctrl+C), jangan tutup jendela ini dengan X,")
        say("supaya skrip sempat logout dari SIS.")
        code = 0
        try:
            folder = args.folder
            while folder is not None:
                if not download_folder(p, context, folder):
                    break
                say("")
                name = input(f"Folder berikutnya di {root}\\ (kosong = selesai): ").strip()
                folder = root / name if name else None
        except SessionDenied:
            say("")
            say("SIS menolak: terlalu banyak sesi aktif untuk akun ini. Skrip berhenti.")
            code = 1
        except (KeyboardInterrupt, EOFError):
            say("")
            say("Dibatalkan.")
        finally:
            try:
                logout(context)
            except Exception as e:  # a broken connection after Ctrl+C
                say(f"Logout SIS gagal ({e}); logout sendiri di Chrome kalau masih terbuka.")
            try:
                context.close()
            except Error:
                pass
    return code


if __name__ == "__main__":
    sys.exit(main())
