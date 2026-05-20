"""
讀取出隊 Excel（all in one 直企格式），寫入 Supabase，並生成 P1/P2 截圖上傳 Storage。
資料來源：直企P1（出隊資訊）、直企P2（隊員名單、留守資料）。
用法：
  python3 scripts/normalize.py                    # 處理 data/raw/xlsx/ 下所有 xlsx
  python3 scripts/normalize.py data/raw/xlsx/foo.xlsx
環境變數（或 .env）：
  SUPABASE_URL            — Supabase project URL
  SUPABASE_SERVICE_KEY    — service_role key（寫入權限）
"""
import re
import sys
import subprocess
import tempfile
from pathlib import Path

import fitz
import openpyxl
from openpyxl.worksheet.properties import PageSetupProperties
from openpyxl.worksheet.page import PageMargins
from PIL import Image, ImageOps
from dotenv import load_dotenv
from supabase import create_client, Client

load_dotenv()

import os
SUPABASE_URL = os.environ["SUPABASE_URL"]
SUPABASE_KEY = os.environ["SUPABASE_SERVICE_KEY"]

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

XLSX_STAGING    = Path(__file__).parent.parent / "data" / "raw"
XLSX_DIR        = Path(__file__).parent.parent / "data" / "raw" / "xlsx"
TXT_DIR         = Path(__file__).parent.parent / "data" / "raw" / "txt"
STATIC_GPX      = Path(__file__).parent.parent / "app" / "static" / "gpx"
STATIC_MAPS     = Path(__file__).parent.parent / "app" / "static" / "maps"
STATIC_PREVIEWS = Path(__file__).parent.parent / "app" / "static" / "previews"

GPX_EXTS    = {".gpx", ".kml"}
MAP_EXTS    = {".pdf"}
RECORD_EXTS = {".txt", ".md", ".docx", ".pdf"}

COUNTY_NORMALIZE = {
    "臺北市": "台北", "台北市": "台北",
    "新北市": "新北",
    "基隆市": "基隆",
    "宜蘭縣": "宜蘭",
    "桃園市": "桃園",
    "新竹市": "新竹", "新竹縣": "新竹",
    "苗栗縣": "苗栗",
    "臺中市": "台中", "台中市": "台中",
    "花蓮縣": "花蓮",
    "彰化縣": "彰化",
    "南投縣": "南投",
    "雲林縣": "雲林",
    "嘉義市": "嘉義", "嘉義縣": "嘉義",
    "臺南市": "台南", "台南市": "台南",
    "高雄市": "高雄",
    "屏東縣": "屏東",
    "臺東縣": "台東", "台東縣": "台東",
}

ROLE_MAP = {"領": "領隊", "嚮": "嚮導", "隊": "隊員", "新": "新生"}


def roc_to_iso(text: str) -> str | None:
    m = re.search(r"(\d+)\s*年\s*(\d+)\s*月\s*(\d+)\s*日", str(text))
    if not m:
        return None
    y = int(m.group(1)) + 1911
    mo, d = int(m.group(2)), int(m.group(3))
    return f"{y:04d}-{mo:02d}-{d:02d}"


def extract_county_region(location: str):
    county = None
    for official, display in COUNTY_NORMALIZE.items():
        if official in location:
            county = display
            break
    region = None
    m2 = re.search(r"[縣市](.{1,6}?)[鄉鎮市區]", location)
    if m2:
        region = m2.group(1)
    return county, region


def capture_sheet_range(xlsx_path: Path, sheet_name: str, cell_range: str, output_path: Path):
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        wb = openpyxl.load_workbook(xlsx_path, data_only=True)
        ws = wb[sheet_name]
        ws.print_area = cell_range
        if ws.sheet_properties.pageSetUpPr is None:
            ws.sheet_properties.pageSetUpPr = PageSetupProperties(fitToPage=True)
        else:
            ws.sheet_properties.pageSetUpPr.fitToPage = True
        ws.page_setup.fitToWidth = 1
        ws.page_setup.fitToHeight = 1
        ws.page_setup.scale = None
        ws.page_margins = PageMargins(left=0.2, right=0.2, top=0.2, bottom=0.2, header=0, footer=0)
        for name in list(wb.sheetnames):
            if name != sheet_name:
                del wb[name]
        tmp_xlsx = tmp / "preview.xlsx"
        wb.save(tmp_xlsx)
        result = subprocess.run(
            ["libreoffice", "--headless", "--convert-to", "pdf",
             str(tmp_xlsx), "--outdir", str(tmp)],
            capture_output=True, timeout=60
        )
        if result.returncode != 0:
            print(f"    ⚠ LibreOffice 失敗：{result.stderr.decode()[:200]}")
            return
        pdf_path = tmp / "preview.pdf"
        if not pdf_path.exists():
            print(f"    ⚠ PDF 未生成")
            return
        doc = fitz.open(pdf_path)
        pix = doc[0].get_pixmap(matrix=fitz.Matrix(2.0, 2.0))
        output_path.parent.mkdir(parents=True, exist_ok=True)
        pix.save(str(output_path))


def trim_whitespace(img: Image.Image, padding: int = 15) -> Image.Image:
    gray = img.convert("L")
    bbox = ImageOps.invert(gray).getbbox()
    if not bbox:
        return img
    l, t, r, b = bbox
    return img.crop((max(0, l - padding), max(0, t - padding),
                     min(img.width, r + padding), min(img.height, b + padding)))


def build_a4_preview(paths: list[Path], output_path: Path):
    A4_W, A4_H, GAP = 1240, 1754, 16
    imgs = [trim_whitespace(Image.open(p)) for p in paths if p.exists()]
    if not imgs:
        return
    target_w = A4_W
    resized = [img.resize((target_w, round(img.height * target_w / img.width)), Image.LANCZOS)
               for img in imgs]
    total_h = sum(img.height for img in resized) + GAP * (len(resized) - 1)
    if total_h > A4_H:
        scale = A4_H / total_h
        target_w = round(A4_W * scale)
        resized = [img.resize((target_w, round(img.height * target_w / img.width)), Image.LANCZOS)
                   for img in imgs]
        total_h = sum(img.height for img in resized) + GAP * (len(resized) - 1)
    canvas = Image.new("RGB", (max(img.width for img in resized), total_h), "white")
    y = 0
    for img in resized:
        canvas.paste(img, (0, y))
        y += img.height + GAP
    output_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(str(output_path))


def storage_upload(bucket: str, path: str, local_path: Path, content_type: str):
    data = local_path.read_bytes()
    try:
        supabase.storage.from_(bucket).upload(
            path, data,
            file_options={"content-type": content_type, "upsert": "true"},
        )
    except Exception as e:
        print(f"    ⚠ 上傳 {bucket}/{path} 失敗：{e}")


def scan_static_files(exp_id: int, exp_name: str):
    def resolve_dir(base: Path) -> Path | None:
        by_id   = base / str(exp_id)
        by_name = base / exp_name
        if by_id.is_dir():
            return by_id
        if by_name.is_dir():
            by_name.rename(by_id)
            return by_id
        return None

    gpx_dir = resolve_dir(STATIC_GPX)
    if gpx_dir:
        for f in sorted(gpx_dir.iterdir()):
            if f.suffix.lower() not in GPX_EXTS:
                continue
            storage_path = f"{exp_id}/{f.name}"
            existing = supabase.table("gpx_files").select("id").eq("file_path", storage_path).execute()
            if not existing.data:
                supabase.table("gpx_files").insert(
                    {"expedition_id": exp_id, "filename": f.name, "file_path": storage_path}
                ).execute()
            storage_upload("gpx", storage_path, f, "application/gpx+xml")

    maps_dir = resolve_dir(STATIC_MAPS)
    if maps_dir:
        for f in sorted(maps_dir.iterdir()):
            if f.suffix.lower() not in MAP_EXTS:
                continue
            storage_path = f"{exp_id}/{f.name}"
            existing = supabase.table("map_files").select("id").eq("file_path", storage_path).execute()
            if not existing.data:
                supabase.table("map_files").insert(
                    {"expedition_id": exp_id, "filename": f.name, "file_path": storage_path}
                ).execute()
            storage_upload("maps", storage_path, f, "application/pdf")

    txt_dir = resolve_dir(TXT_DIR)
    if txt_dir:
        for f in sorted(txt_dir.iterdir()):
            if f.suffix.lower() not in RECORD_EXTS:
                continue
            existing = supabase.table("records").select("id").eq("expedition_id", exp_id).eq("filename", f.name).execute()
            if existing.data:
                continue
            ext = f.suffix.lower()
            if ext == ".docx":
                from docx import Document
                doc = Document(f)
                parts = [p.text for p in doc.paragraphs if p.text.strip()]
                for table in doc.tables:
                    for row in table.rows:
                        row_text = "  ".join(c.text.strip() for c in row.cells if c.text.strip())
                        if row_text:
                            parts.append(row_text)
                content = "\n".join(parts)
            elif ext == ".pdf":
                doc = fitz.open(str(f))
                content = "\n".join(page.get_text() for page in doc)
                doc.close()
            else:
                content = f.read_text(encoding="utf-8", errors="replace")
            supabase.table("records").insert(
                {"expedition_id": exp_id, "filename": f.name, "content": content}
            ).execute()

    print(f"    靜態檔案已掃描")


def parse_p1(ws):
    name = str(ws["D2"].value or "").strip() or None
    date_start = roc_to_iso(ws["C3"].value or "")
    date_end = roc_to_iso(ws["C4"].value or "")
    entry_loc = str(ws["F3"].value or "")
    exit_loc  = str(ws["F4"].value or "")
    county, region = extract_county_region(entry_loc)
    county_exit, region_exit = extract_county_region(exit_loc)
    return name, date_start, date_end, county, region, county_exit, region_exit


def parse_p2(ws):
    desc_parts = []
    for r in range(3, 12):
        label = str(ws.cell(r, 13).value or "").strip()
        value = str(ws.cell(r, 14).value or "").strip()
        if label and value:
            desc_parts.append(f"{label}：{value}")
    garmin = str(ws["D10"].value or "").strip()
    if garmin.startswith("http"):
        desc_parts.append(f"Garmin 追蹤：{garmin}")
    notes = str(ws["D11"].value or "").strip()
    if notes:
        desc_parts.append(f"注意事項：{notes}")
    description = "\n".join(desc_parts) or None

    members: list[tuple[str, str | None, str | None, str | None]] = []
    current_role: str | None = None
    for r in range(15, ws.max_row + 1):
        role_abbr = str(ws.cell(r, 1).value or "").strip()
        dept_raw  = str(ws.cell(r, 2).value or "").strip()
        name_raw  = str(ws.cell(r, 4).value or "").strip()
        exp_raw   = str(ws.cell(r, 6).value or "").strip()
        if role_abbr in ROLE_MAP:
            current_role = ROLE_MAP[role_abbr]
        name = name_raw.split("\n")[0].strip()
        department = dept_raw.split("\n")[0].strip() or None
        experience = exp_raw.split("\n")[0].strip() or None
        if name and current_role is not None:
            members.append((name, current_role, department, experience))

    return description, members


P1_NAMES = ["直企P1(列印)", "直企列印 P1"]
P2_NAMES = ["直企P2(列印)", "直企列印 P2"]


def find_sheet(wb, candidates: list[str]) -> str | None:
    for name in candidates:
        if name in wb.sheetnames:
            return name
    return None


def normalize(xlsx_path: Path):
    wb = openpyxl.load_workbook(xlsx_path, data_only=True)

    p1_name = find_sheet(wb, P1_NAMES)
    if not p1_name:
        print(f"  ⚠ 找不到 P1 sheet，跳過 {xlsx_path.name}")
        return

    ws_p1 = wb[p1_name]
    name, date_start, date_end, county, region, county_exit, region_exit = parse_p1(ws_p1)

    if not name:
        print(f"  ⚠ 無法取得出隊名稱，跳過 {xlsx_path.name}")
        return
    if not date_start:
        print(f"  ⚠ 無法解析 date_start，跳過 {xlsx_path.name}")
        return

    description, members = None, []
    p2_name = find_sheet(wb, P2_NAMES)
    if p2_name:
        description, members = parse_p2(wb[p2_name])
    else:
        print(f"  ⚠ 找不到 P2 sheet，隊員與留守資料略過")

    existing = supabase.table("expeditions").select("id").eq("name", name).eq("date_start", date_start).execute()
    if existing.data:
        exp_id = existing.data[0]["id"]
        print(f"  → 已存在（id={exp_id}）：{name}，補掃靜態檔案")
        scan_static_files(exp_id, name)
        return

    result = supabase.table("expeditions").insert({
        "name": name,
        "date_start": date_start,
        "date_end": date_end,
        "county": county,
        "region": region,
        "region_exit": region_exit,
        "description": description,
    }).execute()
    exp_id = result.data[0]["id"]

    if members:
        supabase.table("members").insert([
            {"expedition_id": exp_id, "name": mname, "role": mrole, "department": mdept, "experience": mexp}
            for mname, mrole, mdept, mexp in members
        ]).execute()

    counties = {c for c in {county, county_exit} if c}
    if counties:
        supabase.table("expedition_counties").insert([
            {"expedition_id": exp_id, "county": c} for c in counties
        ]).execute()

    XLSX_DIR.mkdir(parents=True, exist_ok=True)
    xlsx_dest = XLSX_DIR / xlsx_path.name
    if xlsx_path != xlsx_dest and not xlsx_dest.exists():
        xlsx_path.rename(xlsx_dest)
        xlsx_path = xlsx_dest

    scan_static_files(exp_id, name)

    print(f"  ✓ 已插入：{name}（id={exp_id}）")
    print(f"    日期：{date_start} ～ {date_end or '—'}")
    print(f"    地點：{county or '—'} · {region or '—'}")
    print(f"    隊員：{len(members)} 人")

    STATIC_PREVIEWS.mkdir(parents=True, exist_ok=True)
    preview_local = STATIC_PREVIEWS / f"{exp_id}.png"
    with tempfile.TemporaryDirectory() as _tmp:
        _tmp = Path(_tmp)
        p1_path = _tmp / "p1.png"

        print(f"    截圖 P1...", end=" ", flush=True)
        if p1_name:
            capture_sheet_range(xlsx_path, p1_name, "A2:G27", p1_path)
            print("完成" if p1_path.exists() else "失敗")
        else:
            print("跳過")

        build_a4_preview([p1_path], preview_local)

    if preview_local.exists():
        storage_upload("previews", f"{exp_id}.png", preview_local, "image/png")
        supabase.table("expeditions").update({"preview_image": f"{exp_id}.png"}).eq("id", exp_id).execute()
        print(f"    預覽圖：{exp_id}.png")


def main():
    target = Path(sys.argv[1]) if len(sys.argv) >= 2 else XLSX_STAGING
    files = sorted(target.glob("*.xlsx")) if target.is_dir() else [target]

    for f in files:
        print(f"\n處理：{f.name}")
        try:
            normalize(f)
        except Exception as e:
            print(f"  ✗ 錯誤：{e}")


if __name__ == "__main__":
    main()
