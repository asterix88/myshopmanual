"""Merge a folder of single SIS documents into one manual with bookmarks.

sis-download.bat saves every SIS document as its own PDF ("NNN Title.pdf")
plus daftar-dokumen.txt (number, title, book, date). A folder holding a
susunan.txt is shipped as ONE manual instead of one file per document:

    # Engine (C15/C18)                <- chapter (bookmark level 1)
    ## Fuel system                    <- group (level 2)
    121 Fuel System - Prime           <- document (level 3), by its file number

The words after the number are the bookmark title (the file's own title
when there are none). A line starting with // is a note; "// 090 ..."
leaves document 090 out of the manual. PDFs of the folder that
susunan.txt does not name at all (new downloads) go to a chapter
"Others" at the end, so nothing is lost. Without a
susunan.txt, build_packages writes a first one from daftar-dokumen.txt
(see draft_susunan): chapters from the SIS book, groups from words in the
titles. It is a plain text file, to be edited in Notepad.
"""

import hashlib
import json
import re
from pathlib import Path

import pymupdf

SUSUNAN_FILE = "susunan.txt"
LIST_FILE = "daftar-dokumen.txt"
OTHERS = "Others"

DOC_NUMBER = re.compile(r"^(\d{3,})\b\s*(.*)$")


def is_merged_folder(folder: Path) -> bool:
    """A folder that is shipped as one manual."""
    return (folder / SUSUNAN_FILE).exists() or (folder / LIST_FILE).exists()


def numbered_pdfs(folder: Path) -> dict[str, Path]:
    """The folder's "NNN Title.pdf" files by number. A PDF without a
    number (saved by hand) gets its file name as key: no susunan.txt line
    can name it, so it always lands under Others rather than being lost."""
    out = {}
    for pdf in sorted(folder.glob("*.pdf")):
        m = DOC_NUMBER.match(pdf.stem)
        out[m.group(1) if m else pdf.name] = pdf
    return out


def needs_draft(folder: Path) -> bool:
    """True when susunan.txt is missing or holds nothing yet: an empty
    susunan.txt is how a folder without daftar-dokumen.txt (downloaded
    before that list existed) asks to be merged."""
    path = folder / SUSUNAN_FILE
    return not path.exists() or not read_susunan(path)[0]


def doc_title(pdf: Path) -> str:
    m = DOC_NUMBER.match(pdf.stem)
    return (m.group(2) if m else pdf.stem).strip() or pdf.stem


def read_susunan(path: Path) -> tuple[list[tuple[int, str, str | None]], set[str]]:
    """The outline as (level, title, document number or None) rows, and
    the numbers left out on purpose ("// 090 ...")."""
    rows, left_out = [], set()
    for raw in path.read_text(encoding="utf-8-sig").splitlines():
        line = raw.strip()
        if line.startswith("//"):
            m = DOC_NUMBER.match(line[2:].strip())
            if m:
                left_out.add(m.group(1))
            continue
        if not line:
            continue
        if line.startswith("##"):
            rows.append((2, line.lstrip("#").strip(), None))
        elif line.startswith("#"):
            rows.append((1, line.lstrip("#").strip(), None))
        else:
            m = DOC_NUMBER.match(line)
            if m:
                rows.append((3, m.group(2).strip(), m.group(1)))
    return rows, left_out


def plan(folder: Path) -> tuple[list[tuple[int, str, Path | None]], list[str], list[Path]]:
    """What goes into the manual, in order: (bookmark level, title, PDF or
    None for a chapter or group heading). Also returns the numbers listed
    but missing and the PDFs not listed (those are put under Others)."""
    pdfs = numbered_pdfs(folder)
    rows, left_out = read_susunan(folder / SUSUNAN_FILE)
    out, missing, used = [], [], set(left_out)
    depth = 0  # 0 = no chapter yet, 1 = in a chapter, 2 = in a group
    for level, title, number in rows:
        if level < 3:
            depth = level if level == 1 or depth else 1
            out.append((depth, title, None))
            continue
        pdf = pdfs.get(number)
        if pdf is None:
            missing.append(number)
            continue
        used.add(number)
        out.append((depth + 1, title or doc_title(pdf), pdf))
    unlisted = [pdf for number, pdf in pdfs.items() if number not in used]
    if unlisted:
        out.append((1, OTHERS, None))
        out += [(2, doc_title(pdf), pdf) for pdf in unlisted]
    return out, missing, unlisted


def fingerprint(folder: Path) -> str:
    """Changes whenever susunan.txt or any of the folder's PDFs changes."""
    h = hashlib.sha256((folder / SUSUNAN_FILE).read_bytes())
    for pdf in sorted(folder.glob("*.pdf")):
        st = pdf.stat()
        h.update(f"{pdf.name}|{st.st_size}|{st.st_mtime_ns}".encode())
    return h.hexdigest()


def merge_folder(folder: Path, target: Path, title: str) -> tuple[bool, list[str], list[Path]]:
    """Writes the folder's manual to target. Returns (rebuilt, missing
    numbers, unlisted PDFs). A folder that has not changed since the last
    run is not merged again, so the manual keeps its exact bytes (and the
    app does not see a new version)."""
    items, missing, unlisted = plan(folder)
    stamp = target.with_suffix(".json")
    key = fingerprint(folder)
    if target.exists() and stamp.exists():
        try:
            if json.loads(stamp.read_text())["fingerprint"] == key:
                return False, missing, unlisted
        except (ValueError, KeyError, OSError):
            pass

    out = pymupdf.open()
    toc = []
    pending: list[tuple[int, str]] = []  # headings waiting for their first page
    for level, name, pdf in items:
        if pdf is None:
            # A heading replaces one of its level (or deeper) still waiting:
            # an empty chapter or group is left out.
            pending = [(lvl, h) for lvl, h in pending if lvl < level]
            pending.append((level, name))
            continue
        page = out.page_count + 1
        toc += [[lvl, heading, page] for lvl, heading in pending]
        pending = []
        toc.append([level, name, page])
        with pymupdf.open(pdf) as doc:
            out.insert_pdf(doc)
    if out.page_count == 0:
        raise ValueError(f"{folder}: tidak ada PDF yang bisa digabung")
    out.set_toc(toc)
    out.set_metadata({"title": title, "producer": "MyManual"})
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.with_suffix(".tmp")
    out.save(tmp, garbage=3, deflate=True)
    out.close()
    tmp.replace(target)
    stamp.write_text(json.dumps({"fingerprint": key}))
    return True, missing, unlisted


# --- the first susunan.txt, written from daftar-dokumen.txt -----------------
#
# Each kind of SIS document (Testing And Adjusting, Operation And
# Maintenance Manual, ...) has its own rules, picked by the book names in
# daftar-dokumen.txt. A rule set says:
#   books:    SIS book code -> chapter
#   chapters: chapter order (others follow, then Others)
#   titles:   (chapter, title pattern, book codes or None = any book): a
#             title that belongs to another chapter than its book's
#   groups:   (chapter, group, title pattern, book codes or None), tried in
#             order; the group order in a chapter follows this list too. A
#             rule with book codes also gives the chapter (titles do too)
#   default:  chapter for a document no rule and no known book places
#   no_book:  (title pattern, book code): a document SIS lists without a
#             book that belongs to that book
#   by_date:  a document without a book belongs to the book that alone
#             has documents of the same date
#   lead:     (optional) (chapter or None = any, title pattern): titles that
#             go first in a group, in this order
# Inside a group, documents are sorted by title.

TESTING_ADJUSTING = {
    "books": {
        "M0118654": "Hydraulic & Machine Systems",
        "M0109908": "Work Tool Control",
        "M0082989": "Cat Grade 2D / 3D",
        "UENR4125": "Air Conditioning & Heating",
        "M0085479": "Air Conditioning & Heating",
        "M0083909": "Machine Security System",
        "RENR7911": "Product Link",
        "RENR8143": "Product Link",
        "UENR0997": "Engine (C15/C18)",
        "SENR9832": "Engine (C15/C18)",
        "M0119606": "Work Area Vision",
    },
    "chapters": [
        "General Information", "Engine (C15/C18)", "Hydraulic & Machine Systems", "Work Tool Control",
        "Cat Grade 2D / 3D", "Air Conditioning & Heating", "Machine Security System", "Product Link",
        "Work Area Vision",
    ],
    "titles": [
        ("General Information", r"^(General Testing And Adjusting Information|Specifications|Operational Checks"
                                r"|Visual Inspection|Machine Preparation|Hydraulic System Warm-Up"
                                r"|System Pressure - Release)$", ("M0118654",)),
        ("Engine (C15/C18)", r"^Engine Performance", None),
        ("Hydraulic & Machine Systems", r"Joystick", None),
        ("Cat Grade 2D / 3D", r"Web Interface", None),
    ],
    "groups": [
        ("General Information", "General", r"^General Testing|^Specifications$|^Operational Checks|^Visual Inspection", None),
        ("General Information", "Machine preparation", r"^Machine Preparation$|Warm-Up|^System Pressure - Release", None),
        ("Engine (C15/C18)", "Engine performance", r"^Engine Performance", None),
        ("Engine (C15/C18)", "Fuel system", r"Fuel|Electronic Unit Injector", None),
        ("Engine (C15/C18)", "Air inlet & exhaust",
         r"Air Inlet|Exhaust|Turbocharger|Aftercooler|Inlet Manifold|Crankcase Pressure", None),
        ("Engine (C15/C18)", "Lubrication system", r"Engine Oil|Oil Consumption|Bearing Wear", None),
        ("Engine (C15/C18)", "Cooling system", r"Cooling System|Water Temperature|Water Pump", None),
        ("Engine (C15/C18)", "Valve & timing", r"Valve Lash|Brake Lash|Top Center|Gear Group", None),
        ("Engine (C15/C18)", "Basic engine",
         r"Piston|Liner|Connecting Rod|Main Bearing|Cylinder Block|Flywheel|Vibration Damper", None),
        ("Engine (C15/C18)", "Electrical system", r"Charging|Starting|Battery|Pinion Clearance", None),
        ("Hydraulic & Machine Systems", "Relief valve", r"Relief Valve", None),
        ("Hydraulic & Machine Systems", "Main pump & pump control", r"Main Pump|Pump Control", None),
        ("Hydraulic & Machine Systems", "Pilot & accumulator", r"Pilot Pressure|Accumulator", None),
        ("Hydraulic & Machine Systems", "Air purge", r"Air - Purge", None),
        ("Hydraulic & Machine Systems", "Travel", r"Travel", None),
        ("Hydraulic & Machine Systems", "Swing", r"Swing", None),
        ("Hydraulic & Machine Systems", "Cylinder", r"Cylinder (Drift|Speed)", None),
        ("Hydraulic & Machine Systems", "Calibration", r"Calibrate", None),
        ("Work Tool Control", "Relief valve & parameters", r"Relief|Parameter", None),
        ("Work Tool Control", "Solenoid valve calibration", r"Solenoid Valve", None),
        ("Work Tool Control", "Work tool setup", r"Work Tool|System Identification", None),
        ("Cat Grade 2D / 3D", "Calibration", r"^Calibration|Imu|Bucket Sensor|Service Tool Accuracy", None),
        ("Cat Grade 2D / 3D", "Configuration & setup", r"Configuration|Setup Sequence", None),
        ("Cat Grade 2D / 3D", "Licenses", r"Licenses", None),
        ("Cat Grade 2D / 3D", "Accuracy tests", r"Accuracy|Test|Bucket Wear", None),
        ("Air Conditioning & Heating", "Tools & preparation",
         r"Manifold Gauge|Required Tools|Preparation|Publications", None),
        ("Air Conditioning & Heating", "Refrigerant", r"Refrigerant", None),
        ("Air Conditioning & Heating", "Performance tests", r"Performance|Heat|Compressor Protection", None),
    ],
    "default": "Engine (C15/C18)",  # SIS shows no book for most engine documents
    "no_book": [],
    "by_date": False,
}

# The machine's own OMM (and documents SIS lists without a book) is split
# by title into Safety / Operation (for the operator) / Maintenance (for
# the mechanic) / Reference Information; each supplement book is a chapter.
OMM_MAIN = ("M0112739", "")
OPERATION_MAINTENANCE = {
    "books": {
        "SEBU6250": "Fluids Recommendations",
        "M0109053": "Monitoring System",
        "M0082987": "Cat Grade 2D / 3D",
        "M0133587": "Cat Command (Remote Control)",
        "M0133245": "Cat Command (Remote Control)",
        "M0079764": "Cat Command (Remote Control)",
        "M0085431": "Regulatory Compliance",
    },
    "chapters": [
        "Safety", "Operation", "Maintenance", "Fluids Recommendations", "Monitoring System",
        "Cat Grade 2D / 3D", "Cat Command (Remote Control)", "Regulatory Compliance", "Reference Information",
    ],
    "titles": [],
    "groups": [
        ("Safety", "Safety messages", r"^Safety Messages$|^Additional Messages$", OMM_MAIN),
        ("Safety", "Hazard prevention",
         r"General Hazard|Crushing Prevention|Burn Prevention|Fire Prevention|^Fire Safety|Fire Extinguisher"
         r"|Electrical Storm|High Pressure Fuel Lines", OMM_MAIN),
        ("Safety", "Operator safety",
         r"^Before Starting Engine$|Visibility Information|Restricted Visibility|Slope Operation|Sound Information"
         r"|^Operator Station$|^Guards|Emergency Rescue|^Track Information$", OMM_MAIN),
        ("Operation", "Machine information",
         r"^Specifications$|Lifting Capacities|Boom stick bucket Combinations|Plate Locations"
         r"|Emissions Certification|Adjustable Gauge", OMM_MAIN),
        ("Operation", "Before operation", r"^Mounting And Dismounting|^Daily Inspection|^Before Operation$", OMM_MAIN),
        ("Operation", "Cab & operator station",
         r"^Alternate Exit|^Seat$|^Seat Belt$|Seat Belt Reminder|^Mirror|^Camera$|^Window \(Front\)|^Cab Door"
         r"|Roof Hatch|Sun Screen|Platform Light|Compartment Light|Wavs", OMM_MAIN),
        ("Operation", "Controls & monitoring",
         r"^Operator Controls$|^Joystick Controls|^Monitoring System|Air Conditioning And Heating Control|^Radio$"
         r"|^Machine Security System$|^Product Link$|Battery Disconnect Switch|Travel Control|Smartboom Control"
         r"|^Work Tool Control|Fuel Tank Shutoff|Fuel Transfer Pump", OMM_MAIN),
        ("Operation", "Engine starting", r"^Engine Starting|Warm-Up", OMM_MAIN),
        ("Operation", "Machine operation",
         r"^Operation$|^Operation Information|Operating Technique|Boom, Stick And Bucket Operation|Travel In Water"
         r"|Frozen Ground|^Lifting Objects|^Demolition|Smartboom Operation|^Work Tool Operation|^Work Tools$"
         r"|Quick Coupler Operation", OMM_MAIN),
        ("Operation", "Parking & stopping",
         r"^Stopping The Machine|^Parking$|Freezing Conditions|^Stopping The Engine|^Engine Stopping"
         r"|Equipment Lowering|Leaving The Machine", OMM_MAIN),
        ("Operation", "Transport & storage",
         r"Shipping The Machine|Lifting And Tying Down|Securing The Machine|Towing The Machine|Machine Storage",
         OMM_MAIN),
        ("Maintenance", "Before maintenance",
         r"Prepare The Machine For Maintenance|Access Door|System Pressure Release|^Welding|Severe Service"
         r"|Counterweight Removal|Bucket - Remove And Install|Sun Gear Removal", OMM_MAIN),
        ("Maintenance", "Schedule & capacities",
         r"Maintenance Interval Schedule|Service Interval Chart|Capacities|Lubricant Viscosities|S·o·s Information",
         OMM_MAIN),
        ("Maintenance", "Engine", r"^Engine Oil|Air Cleaner|Engine Air Filter|^Belt|Valve Lash|Ether Starting Aid",
         OMM_MAIN),
        ("Maintenance", "Fuel system", r"^Fuel", OMM_MAIN),
        ("Maintenance", "Cooling system", r"Cooling System|Radiator", OMM_MAIN),
        ("Maintenance", "Hydraulic system", r"Hydraulic|Oil Filter", OMM_MAIN),
        ("Maintenance", "Swing & final drive", r"Swing|Final Drive", OMM_MAIN),
        ("Maintenance", "Undercarriage", r"Track Adjustment|Undercarriage|Ultrasonic Wear", OMM_MAIN),
        ("Maintenance", "Boom, stick & bucket",
         r"Linkage|Bucket Tips|Bucket Lifting Eye|Boom, Stick, And Frame", OMM_MAIN),
        ("Maintenance", "Electrical",
         r"Fuses|Battery|Grounding Strap|Ground Bond|Lamp|Indicators And Gauges|Travel Alarm", OMM_MAIN),
        ("Maintenance", "Cab & air conditioning",
         r"Cab Air Filter|Air Conditioner|Condenser|Receiver Dryer|Window|Seat Belt - |Camera - Clean|^Film",
         OMM_MAIN),
        ("Reference Information", OTHERS,
         r"Foreword|Reference Material|Declaration Of Conformity|Warranty|Decommissioning", OMM_MAIN),
        ("Fluids Recommendations", "General",
         r"Foreword|Reference Material|Warranty|Contamination Control|Expanded Mining", None),
        ("Fluids Recommendations", "Lubricants",
         r"Lubricant|Oil$|Oils$|Oil Additives|Engine Oil|Grease|Dry Brake", None),
        ("Fluids Recommendations", "Fuel", r"^(?!S·o·s).*(Fuel|Diesel e-Diesel|Renewable Diesel|Pyrolysis|Exhaust Fluid)", None),
        ("Fluids Recommendations", "Coolant", r"^(?!S·o·s).*(Coolant|Antifreeze|Inhibitor)", None),
        ("Fluids Recommendations", "S·O·S analysis", r"S·o·s|Sampling", None),
        ("Monitoring System", "Screens & menus",
         r"General Information|Navigation|Gauges|Machine Warnings|^Information$|Audio|Phone|Air Conditioner"
         r"|Application Menu|Function List|Setting Menu|Electronic Omm|Operator Coaching", None),
        ("Monitoring System", "Assist & E-Fence", r"Assist|E-Fence|Stability", None),
        ("Monitoring System", "Payload & Grade", r"Payload|Grade", None),
        ("Monitoring System", "Work tool", r"Work Tool|Tilt-Rotator|Coupler", None),
        ("Monitoring System", "Maintenance monitoring", r"Planned Maintenance|On Board PM|Hydraulic Health", None),
        ("Cat Grade 2D / 3D", "General",
         r"Safety Messages|General Information|System Components$|Display Description|Startup|Guidance", None),
        ("Cat Grade 2D / 3D", "Calibration", r"Calibration", None),
        ("Cat Grade 2D / 3D", "Troubleshooting", r"Troubleshooting", None),
        ("Cat Command (Remote Control)", "Command Station", r"", ("M0133587",)),
        ("Cat Command (Remote Control)", "Command Console", r"", ("M0133245",)),
        ("Cat Command (Remote Control)", "Remote Control Console with RFID", r"", ("M0079764",)),
        ("Regulatory Compliance", "General & security", r"General Information|Machine Security", None),
        ("Regulatory Compliance", "Product Link", r"Product Link", None),
        ("Regulatory Compliance", "Wireless devices & GPS", r"Wireless|Global Positioning|Radio Frequency", None),
        ("Regulatory Compliance", "Entertainment radio", r"Radio", None),
    ],
    "default": OTHERS,
    "no_book": [
        (r"Wireless Device|Entertainment|Radio Frequency|Global Positioning", "M0085431"),
        (r"^Assist And E-Fence", "M0109053"),
    ],
    "by_date": True,
}

# Systems Operation: the same books as Testing And Adjusting, so the same
# chapters; the machine systems book is grouped per hydraulic circuit, each
# group led by its General Information, Location Of Components and system
# description (see "lead").
SYSTEMS_OPERATION = {
    "books": {
        "M0118653": "Hydraulic & Machine Systems",
        "M0109908": "Work Tool Control",
        "M0081165": "Monitoring System",
        "M0082989": "Cat Grade 2D / 3D",
        "UENR4125": "Air Conditioning & Heating",
        "M0085479": "Air Conditioning & Heating",
        "M0083909": "Machine Security System",
        "RENR7911": "Product Link",
        "RENR8143": "Product Link",
        "UENR0997": "Engine (C15/C18)",
        "SENR9832": "Engine (C15/C18)",
        "M0119606": "Work Area Vision",
        "M0069884": "A-Stop System",
        "SENR7733": "General Information",
        "SENR3981": "General Information",
    },
    "chapters": [
        "General Information", "Engine (C15/C18)", "Hydraulic & Machine Systems", "Work Tool Control",
        "Monitoring System", "Cat Grade 2D / 3D", "Air Conditioning & Heating", "Machine Security System",
        "Product Link", "Work Area Vision", "A-Stop System",
    ],
    "titles": [
        ("General Information", r"^Graphic Color Codes$", ("M0118653",)),
    ],
    "groups": [
        ("Engine (C15/C18)", "General & electronic control", r"^General Information$|Electronic Control", None),
        ("Engine (C15/C18)", "Fuel system", r"Fuel", None),
        ("Engine (C15/C18)", "Air inlet & exhaust", r"Air Inlet|Exhaust", None),
        ("Engine (C15/C18)", "Lubrication system", r"Lubrication", None),
        ("Engine (C15/C18)", "Cooling system", r"Cooling", None),
        ("Engine (C15/C18)", "Basic engine", r"Basic Engine|Compression Brake", None),
        ("Engine (C15/C18)", "Electrical system", r"Electrical", None),
        ("Hydraulic & Machine Systems", "Machine system", r"Machine System|Engine Control", None),
        ("Hydraulic & Machine Systems", "Main pump system", r"Main Pump|Main Hydraulic Pump|Pump Control", None),
        ("Hydraulic & Machine Systems", "Pilot system",
         r"Pilot System|Piston Pump \(Pilot\)|Accumulator \(Pilot\)", None),
        ("Hydraulic & Machine Systems", "Main control valve", r"Main Control Valve|Relief Valve|Check Valve \(Load\)", None),
        ("Hydraulic & Machine Systems", "Boom system", r"Boom", None),
        ("Hydraulic & Machine Systems", "Stick system", r"Stick", None),
        ("Hydraulic & Machine Systems", "Bucket system", r"Bucket", None),
        ("Hydraulic & Machine Systems", "Swing system", r"Swing", None),
        ("Hydraulic & Machine Systems", "Travel system", r"Travel|Final Drive|Swivel", None),
        ("Hydraulic & Machine Systems", "Return system", r"Return|Hydraulic Tank|Oil Cooler", None),
        ("Hydraulic & Machine Systems", "Fan system", r"Fan", None),
        ("Monitoring System", "General & display",
         r"^General Information$|System Schematic|Data Link|Warning Operation|Prestart|Password|Special Instructions"
         r"|^Information$|Application Menu", None),
        ("Monitoring System", "Menus & settings", r"Setting|Feature Menu|Configuration|Calibration", None),
        ("Monitoring System", "Machine functions",
         r"\(Aec\)|^Auto |Heavy Lift|Straight Travel|Fine Swing|Boom Low|Bucket Cylinder Lock|Smart Boom|Work Light"
         r"|Light Flash|Overload|Crane|Tiltrotator|Coupler|^Work Tool$|Vacuum|Regeneration", None),
        ("Monitoring System", "Assist, E-Fence & payload", r"Assist|E-Fence|Payload|Coaching", None),
        ("Monitoring System", "Vision & people detection", r"Visibility|Detect", None),
        ("Monitoring System", "Maintenance & software",
         r"Maintenance|Hydraulic Health|PM Service|^Service|Software|Remote Flash", None),
        ("Monitoring System", "Audio, phone & air conditioner", r"Air Conditioner|Audio|Phone", None),
        ("Air Conditioning & Heating", "General",
         r"General Information|Air Conditioning And Heating System$|Glossary|Service Intervals|Identifying|Condensate"
         r"|Cab Pressurization", None),
        ("Air Conditioning & Heating", "Refrigerant circuit", r"Refrigerant|Compressor|Condenser|Evaporator|Dryer|Orifice", None),
        ("Air Conditioning & Heating", "Controls & electrical", r"Control|Sensor|Relay|Schematic|Blower|Fan|Motor", None),
        ("Air Conditioning & Heating", "Heating", r"Heater", None),
        ("Product Link", "PL121S / PL300", r"", ("RENR7911",)),
        ("Product Link", "PL522 / PL523", r"", ("RENR8143",)),
    ],
    "lead": [
        (None, r"^General Information"),
        ("Engine (C15/C18)", r"^Fuel System$"),
        ("Hydraulic & Machine Systems", r"^Location Of Components"),
        ("Hydraulic & Machine Systems", r"^(Machine|Pilot|Boom|Stick|Bucket|Swing|Travel|Return Hydraulic|Fan Hydraulic)"
                                        r" System$|^Main Control Valve$|^Main Hydraulic Pump$"),
    ],
    "default": "Engine (C15/C18)",  # SIS shows no book for most engine documents
    "no_book": [],
    "by_date": False,
}

# Troubleshooting: every book has the same kinds of documents, so each
# chapter gets the same groups (general, codes, symptoms, tests, ECM).
TS_GENERAL = (r"^General Information|^General Troubleshooting|Service Tools|Diagnostic Capabilities|Connector Locations"
              r"|Component Location|System Schematic|System Overview|Machine Preparation|Visual Inspection"
              r"|Basic Troubleshooting|Welding|Wiring Information|Connector Contact|Service Information Report"
              r"|Emerging Symptom|^Electrical Connectors$|Electronic Service Tools$|Engine Monitoring System")
TS_CODES = (r"Diagnostic Trouble Codes|^(?!Symptom).*Event Code|Diagnostic Code List|Troubleshooting Faults"
            r"|^Mid \d|^Air Conditioning \d")
TS_SYMPTOMS = (r"Symptom|Troubleshooting$|\b(Is|Has|Contains|Problem|Stalls|Misfires|Overspeeds|Cranks)\b|Does Not"
               r"|Will Not|Fails|Not Available|Not Obtained|Discrepancy|Erratic$|Smoke|Shutdown Occurs")
TS_TESTS = r"- Test|- Inspect|- Calibrate"
TS_ECM = (r"ECM|Software|Firmware|Password|Parameters|Configure|Configuration|Install|Replace|Reset|Access|Setup"
          r"|Enable|Retrieve|Zsnap|Trim")
TS_CHAPTERS = ["Machine Electronic Control", "Engine (C15/C18)", "Cat Grade 2D / 3D", "Air Conditioning & Heating"]


def ts_groups(chapter: str) -> list[tuple]:
    extra = [(chapter, "GNSS & radio", r"Gnss|Radio|A6N2", None)] if chapter == "Cat Grade 2D / 3D" else []
    return [
        (chapter, "General information", TS_GENERAL, None),
        (chapter, "Diagnostic & event codes", TS_CODES, None),
        (chapter, "Symptom troubleshooting", TS_SYMPTOMS, None),
        (chapter, "Circuit tests", TS_TESTS, None),
        *extra,
        (chapter, "ECM, software & setup", TS_ECM, None),
    ]


TROUBLESHOOTING = {
    "books": {
        "M0158762": "Machine Electronic Control",
        "M0118623": "Machine Electronic Control",
        "RENR5033": "Engine (C15/C18)",
        "M0082989": "Cat Grade 2D / 3D",
        "UENR4125": "Air Conditioning & Heating",
        "M0085479": "Air Conditioning & Heating",
        "M0083909": "Machine Security System",
        "RENR7911": "Product Link",
        "RENR8143": "Product Link",
        "M0119606": "Work Area Vision",
        "M0069884": "A-Stop System",
    },
    "chapters": TS_CHAPTERS + ["Machine Security System", "Product Link", "Work Area Vision", "A-Stop System"],
    "titles": [],
    "groups": [g for chapter in TS_CHAPTERS for g in ts_groups(chapter)] + [
        ("Product Link", "PL121S / PL300", r"", ("RENR7911",)),
        ("Product Link", "PL522 / PL523", r"", ("RENR8143",)),
    ],
    "lead": [
        (None, r"^General Information"),
        (None, r"^General Troubleshooting"),
        (None, r"^Diagnostic Capabilities"),
        (None, r"^Service Tools"),
        (None, r"Code List$"),
    ],
    # SIS shows no book for many documents of the machine's own
    # electronic control troubleshooting.
    "default": "Machine Electronic Control",
    "no_book": [],
    "by_date": False,
}

# Book name (the words before " - ") -> rule set.
PROFILES = {
    "Testing And Adjusting": TESTING_ADJUSTING,
    "Operation And Maintenance Manual": OPERATION_MAINTENANCE,
    "Systems Operation": SYSTEMS_OPERATION,
    "Troubleshooting": TROUBLESHOOTING,
}
# A kind of document without rules yet: a chapter per SIS book.
NO_RULES = {"books": {}, "chapters": [], "titles": [], "groups": [], "default": OTHERS,
            "no_book": [], "by_date": False}


def read_list(folder: Path) -> list[dict]:
    """daftar-dokumen.txt rows: number, title, book (with its code), date."""
    rows = []
    for line in (folder / LIST_FILE).read_text(encoding="utf-8-sig").splitlines():
        parts = [p.strip() for p in line.split(" | ")]
        if len(parts) > 1 and re.fullmatch(r"i\d+|https?://\S+", parts[-1]):
            parts.pop()  # the SIS number sis-download.bat adds at the end
        m = DOC_NUMBER.match(parts[0])
        if not m:
            continue
        title = re.sub(r"\.pdf$", "", m.group(2), flags=re.I).strip()
        book = re.sub(r"<[^>]+>|&[a-z]+;", "", parts[1]) if len(parts) > 2 else ""
        code = re.search(r"\(([A-Z]+\d+)-\d+\)\s*$", book)
        rows.append({"number": m.group(1), "title": title, "book": book,
                     "code": code.group(1) if code else "", "date": parts[-1] if len(parts) > 1 else ""})
    return rows


def profile_of(rows: list[dict]) -> dict:
    """The rule set of the kind of document most rows belong to."""
    kinds = [r["book"].split(" - ")[0].strip() for r in rows]
    kind = max(set(kinds), key=kinds.count) if kinds else ""
    return PROFILES.get(kind, NO_RULES)


def assign_books(rows: list[dict], profile: dict) -> None:
    """Gives documents SIS lists without a book the book they belong to,
    when a no_book rule or (by_date) a date only one book has says so."""
    dates: dict[str, set[str]] = {}
    for r in rows:
        if r["code"]:
            dates.setdefault(r["date"], set()).add(r["code"])
    for r in rows:
        if r["code"]:
            continue
        for pattern, code in profile["no_book"]:
            if re.search(pattern, r["title"], re.I):
                r["code"] = code
                break
        else:
            books = dates.get(r["date"], set())
            if profile["by_date"] and len(books) == 1:
                r["code"] = next(iter(books))


def chapter_of(row: dict, profile: dict) -> str:
    rules = profile["titles"] + [(ch, pattern, codes) for ch, _, pattern, codes in profile["groups"] if codes]
    for chapter, pattern, codes in rules:
        if re.search(pattern, row["title"], re.I) and (codes is None or row["code"] in codes):
            return chapter
    if row["code"] in profile["books"]:
        return profile["books"][row["code"]]
    if row["code"] and row["book"]:
        # A book not known yet: its own chapter, named after the book.
        return re.sub(r"^.*? - |\s*\([A-Z]+\d+-\d+\)$", "", row["book"]).strip() or OTHERS
    return profile["default"]


def group_of(chapter: str, row: dict, profile: dict) -> str:
    for ch, group, pattern, codes in profile["groups"]:
        if ch == chapter and re.search(pattern, row["title"], re.I) and (codes is None or row["code"] in codes):
            return group
    return OTHERS


def draft_susunan(folder: Path) -> str:
    """A first susunan.txt for the folder, from its daftar-dokumen.txt.
    Every document is listed, same titles too (each SIS copy may differ);
    a title found in two books carries the book's code."""
    files = numbered_pdfs(folder)
    if not (folder / LIST_FILE).exists():
        return draft_from_names(files)
    rows = read_list(folder)
    rows = [r for r in rows if r["number"] in files]
    profile = profile_of(rows)
    assign_books(rows, profile)
    tree: dict[str, dict[str, list[dict]]] = {}
    for row in rows:
        chapter = chapter_of(row, profile)
        tree.setdefault(chapter, {}).setdefault(group_of(chapter, row, profile), []).append(row)

    order = profile["chapters"]

    def chapter_key(name: str) -> tuple[int, bool]:
        return (order.index(name) if name in order else len(order), name == OTHERS)

    def group_key(chapter: str, name: str) -> int:
        groups = list(dict.fromkeys(g for ch, g, _, _ in profile["groups"] if ch == chapter))
        return groups.index(name) if name in groups else len(groups)

    def lead_key(chapter: str, title: str) -> int:
        lead = profile.get("lead", [])
        return next((i for i, (ch, pattern) in enumerate(lead)
                     if ch in (None, chapter) and re.search(pattern, title, re.I)), len(lead))

    lines = [
        "// Susunan manual: # = bab, ## = kelompok, lalu nomor file dan judul bookmark.",
        "// Pindahkan baris untuk mengubah urutan atau kelompok; ganti judul setelah nomor untuk",
        "// mengubah nama bookmark. Untuk tidak memakai dokumen, tulis // di depan barisnya.",
        "// File baru yang belum ada di sini otomatis masuk bab Others di akhir.",
    ]
    for chapter in sorted(tree, key=chapter_key):
        lines += ["", f"# {chapter}"]
        for group in sorted(tree[chapter], key=lambda g: group_key(chapter, g)):
            docs = sorted(tree[chapter][group], key=lambda r: (lead_key(chapter, r["title"]), r["title"].lower(), r["number"]))
            books = {}
            for r in docs:
                if r["code"]:
                    books.setdefault(r["title"].lower(), set()).add(r["code"])
            # A chapter with no groups of its own lists its documents directly.
            if list(tree[chapter]) != [OTHERS]:
                lines.append(f"## {group}")
            for r in docs:
                code = f" ({r['code']})" if len(books.get(r["title"].lower(), ())) > 1 and r["code"] else ""
                lines.append(f"{r['number']} {r['title']}{code}")
    return "\n".join(lines) + "\n"


def draft_from_names(files: dict[str, Path]) -> str:
    """A first susunan.txt from the file names alone (no daftar-dokumen.txt,
    so no SIS book to sort by): one chapter per component, the words before
    the first " - " of the title (Relief Valve (Main) - Test -> Relief
    Valve (Main)); components with one document share a chapter Miscellaneous."""
    chapters: dict[str, list[tuple[str, str]]] = {}
    for number, pdf in files.items():
        if not DOC_NUMBER.match(pdf.stem):
            continue  # unnumbered files go to Others by themselves
        title = doc_title(pdf)
        chapters.setdefault(title.split(" - ")[0].strip(), []).append((number, title))
    lines = [
        "// Susunan manual: # = bab, ## = kelompok, lalu nomor file dan judul bookmark.",
        "// Dibuat dari nama file (folder ini tidak punya daftar-dokumen.txt). Pindahkan baris",
        "// untuk mengubah urutan atau bab; tulis // di depan baris dokumen yang tidak dipakai.",
        "",
    ]
    singles = []
    for name in sorted(chapters, key=str.lower):
        docs = sorted(chapters[name], key=lambda d: (d[1].lower(), d[0]))
        if len(docs) == 1:
            singles.append(docs[0])
            continue
        lines.append(f"# {name}")
        lines += [f"{n} {t}" for n, t in docs]
        lines.append("")
    if singles:
        lines.append("# Miscellaneous")
        lines += [f"{n} {t}" for n, t in sorted(singles, key=lambda d: d[1].lower())]
    return "\n".join(lines).rstrip() + "\n"
