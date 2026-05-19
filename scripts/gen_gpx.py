import os
import sqlite3
import random
import sys
import math
from datetime import datetime, timedelta
from pathlib import Path

if os.getenv("ENV") != "dev":
    print("拒絕執行：gen_gpx.py 只能在 ENV=dev 環境下執行。")
    print("請用：ENV=dev python3 scripts/gen_gpx.py")
    sys.exit(1)

DB_PATH = Path(__file__).parent.parent / "db" / "sttmount_dev.db"
GPX_DIR = Path(__file__).parent.parent / "app" / "static" / "gpx"

COUNTY_CENTER = {
    "台北":  (25.04, 121.56), "新北": (25.01, 121.46), "基隆": (25.13, 121.74),
    "宜蘭":  (24.70, 121.74), "桃園": (24.99, 121.30), "新竹": (24.84, 121.01),
    "苗栗":  (24.57, 120.82), "台中": (24.15, 120.68), "花蓮": (23.97, 121.60),
    "彰化":  (24.07, 120.54), "南投": (23.83, 120.97), "雲林": (23.71, 120.43),
    "嘉義":  (23.48, 120.45), "台南": (23.00, 120.21), "高雄": (22.63, 120.30),
    "屏東":  (22.55, 120.55), "台東": (22.75, 121.15),
}

COUNTY_ELEV = {
    "台北": (400, 1100), "新北": (300, 1100), "基隆": (200, 600),
    "宜蘭": (500, 3500), "桃園": (400, 2000), "新竹": (500, 2600),
    "苗栗": (600, 3500), "台中": (800, 3900), "花蓮": (600, 3800),
    "彰化": (100, 400),  "南投": (800, 3952),"雲林": (100, 1000),
    "嘉義": (600, 2700), "台南": (200, 1000), "高雄": (400, 3000),
    "屏東": (300, 3092), "台東": (400, 3500),
}

GPX_TEMPLATE = """\
<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="sttmount-seed"
     xmlns="http://www.topografix.com/GPX/1/1">
  <metadata><name>{name}</name></metadata>
  <trk>
    <name>{name}</name>
    <trkseg>
{trkpts}
    </trkseg>
  </trk>
</gpx>"""

TRKPT = '      <trkpt lat="{lat:.6f}" lon="{lon:.6f}"><ele>{ele:.1f}</ele><time>{time}</time></trkpt>'


def gen_track(lat0, lon0, elev_range, n_pts=30, date_start="2024-01-01"):
    t0 = datetime.strptime(date_start, "%Y-%m-%d").replace(hour=7, minute=0)
    ele_start, ele_end = elev_range
    # random heading between 30°–120° (northeast to east-southeast)
    heading = math.radians(random.uniform(30, 120))
    step_m = random.uniform(100, 200)
    # degrees per metre
    dlat = math.cos(heading) * step_m / 111_000
    dlon = math.sin(heading) * step_m / (111_000 * math.cos(math.radians(lat0)))

    pts = []
    for i in range(n_pts):
        lat = lat0 + dlat * i + random.gauss(0, 0.00003)
        lon = lon0 + dlon * i + random.gauss(0, 0.00003)
        frac = i / (n_pts - 1)
        # parabolic elevation curve: ascend then plateau
        ele = ele_start + (ele_end - ele_start) * (frac ** 0.6) + random.gauss(0, 20)
        ts = (t0 + timedelta(minutes=10 * i)).strftime("%Y-%m-%dT%H:%M:%SZ")
        pts.append(TRKPT.format(lat=lat, lon=lon, ele=ele, time=ts))
    return "\n".join(pts)


def gen_all():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    rows = conn.execute(
        "SELECT g.id, g.expedition_id, g.filename, g.file_path, "
        "       e.county, e.date_start "
        "FROM gpx_files g JOIN expeditions e ON e.id = g.expedition_id"
    ).fetchall()
    conn.close()

    created = 0
    for row in rows:
        out_path = GPX_DIR / row["file_path"]
        out_path.parent.mkdir(parents=True, exist_ok=True)
        if out_path.exists():
            continue

        county = row["county"] or "南投"
        lat0, lon0 = COUNTY_CENTER.get(county, (23.6, 121.0))
        # small offset so each track in same county differs
        lat0 += random.uniform(-0.1, 0.1)
        lon0 += random.uniform(-0.1, 0.1)
        elev_range = COUNTY_ELEV.get(county, (800, 2500))
        n_pts = random.randint(25, 40)

        trkpts = gen_track(lat0, lon0, elev_range, n_pts, row["date_start"])
        content = GPX_TEMPLATE.format(name=row["filename"], trkpts=trkpts)
        out_path.write_text(content, encoding="utf-8")
        created += 1

    print(f"已產生 {created} 個 GPX 檔案（共 {len(rows)} 筆記錄）。")


if __name__ == "__main__":
    gen_all()
