from fastapi import APIRouter, Request, Query
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from pathlib import Path
from app.models import get_conn

router = APIRouter()
templates = Jinja2Templates(directory=Path(__file__).parent.parent / "templates")

PAGE = 20

# (display, db_counties, col, row)
COUNTY_GRID = [
    ("基隆", ["基隆市"],                3, 1),
    ("台北", ["臺北市", "台北市"],      4, 1),
    ("新北", ["新北市"],                2, 2),
    ("宜蘭", ["宜蘭縣"],                5, 2),
    ("桃園", ["桃園市"],                1, 3),
    ("新竹", ["新竹市", "新竹縣"],      2, 3),
    ("苗栗", ["苗栗縣"],                1, 4),
    ("台中", ["臺中市", "台中市"],      2, 4),
    ("花蓮", ["花蓮縣"],                5, 4),
    ("彰化", ["彰化縣"],                2, 5),
    ("南投", ["南投縣"],                3, 5),
    ("雲林", ["雲林縣"],                2, 6),
    ("嘉義", ["嘉義市", "嘉義縣"],      2, 7),
    ("台南", ["臺南市", "台南市"],      2, 8),
    ("台東", ["台東縣"],                5, 8),
    ("高雄", ["高雄市"],                1, 9),
    ("屏東", ["屏東縣"],                1, 10),
]

COUNTY_MAP = {c[0]: c[1] for c in COUNTY_GRID}

_LEADER_SUB = "(SELECT m.name FROM members m WHERE m.expedition_id = e.id AND m.role = '領隊' LIMIT 1) as leader_name"


def _enrich(rows) -> list[dict]:
    result = []
    for row in rows:
        d = dict(row)
        all_c       = [c for c in (d.get('all_counties') or '').split(',') if c]
        entry       = d.get('county') or ''
        region      = d.get('region') or ''
        region_exit = d.get('region_exit') or ''
        parts = []
        if entry:
            parts.append(f"{entry} · {region}" if region else entry)
        for c in all_c:
            if c != entry:
                parts.append(f"{c} · {region_exit}" if region_exit else c)
        d['counties_display'] = ' / '.join(parts)
        result.append(d)
    return result


@router.get("/", response_class=HTMLResponse)
def home(request: Request, mode: str = "map"):
    with get_conn() as conn:
        row = conn.execute(
            "SELECT MIN(date_start), MAX(COALESCE(date_end, date_start)) FROM expeditions"
        ).fetchone()
    date_min = row[0] or ""
    date_max = row[1] or ""
    return templates.TemplateResponse("index.html", {
        "request": request,
        "county_grid": COUNTY_GRID,
        "initial_mode": mode,
        "date_min": date_min,
        "date_max": date_max,
    })


# ── Fragment endpoints ─────────────────────────────────────────────────────

@router.get("/fragment/recent", response_class=HTMLResponse)
def fragment_recent(request: Request, offset: int = Query(0)):
    with get_conn() as conn:
        rows = conn.execute(f"""
            SELECT e.*, GROUP_CONCAT(DISTINCT ec.county) as all_counties, {_LEADER_SUB}
            FROM expeditions e
            LEFT JOIN expedition_counties ec ON e.id = ec.expedition_id
            GROUP BY e.id ORDER BY COALESCE(e.date_end, e.date_start) DESC LIMIT {PAGE+1} OFFSET {offset}
        """).fetchall()
    has_more = len(rows) > PAGE
    return templates.TemplateResponse("_results.html", {
        "request": request, "items": _enrich(rows[:PAGE]), "has_more": has_more,
    })


@router.get("/fragment/county/{name}", response_class=HTMLResponse)
def fragment_county(request: Request, name: str, offset: int = Query(0)):
    with get_conn() as conn:
        rows = conn.execute(f"""
            SELECT e.*, GROUP_CONCAT(DISTINCT ec_all.county) as all_counties, {_LEADER_SUB}
            FROM expeditions e
            JOIN expedition_counties ec_filter ON e.id = ec_filter.expedition_id
            LEFT JOIN expedition_counties ec_all ON e.id = ec_all.expedition_id
            WHERE ec_filter.county = ?
            GROUP BY e.id ORDER BY COALESCE(e.date_end, e.date_start) DESC LIMIT {PAGE+1} OFFSET {offset}
        """, (name,)).fetchall()
    has_more = len(rows) > PAGE
    return templates.TemplateResponse("_results.html", {
        "request": request, "items": _enrich(rows[:PAGE]), "has_more": has_more,
    })


@router.get("/fragment/date", response_class=HTMLResponse)
def fragment_date(request: Request, date_from: str | None = Query(None), date_to: str | None = Query(None), offset: int = Query(0)):
    with get_conn() as conn:
        if date_from and date_to:
            rows = conn.execute(f"""
                SELECT e.*, GROUP_CONCAT(DISTINCT ec.county) as all_counties, {_LEADER_SUB}
                FROM expeditions e
                LEFT JOIN expedition_counties ec ON e.id = ec.expedition_id
                WHERE e.date_start BETWEEN ? AND ?
                GROUP BY e.id ORDER BY COALESCE(e.date_end, e.date_start) DESC LIMIT {PAGE+1} OFFSET {offset}
            """, (date_from, date_to)).fetchall()
        elif date_from:
            rows = conn.execute(f"""
                SELECT e.*, GROUP_CONCAT(DISTINCT ec.county) as all_counties, {_LEADER_SUB}
                FROM expeditions e
                LEFT JOIN expedition_counties ec ON e.id = ec.expedition_id
                WHERE e.date_start >= ?
                GROUP BY e.id ORDER BY COALESCE(e.date_end, e.date_start) DESC LIMIT {PAGE+1} OFFSET {offset}
            """, (date_from,)).fetchall()
        elif date_to:
            rows = conn.execute(f"""
                SELECT e.*, GROUP_CONCAT(DISTINCT ec.county) as all_counties, {_LEADER_SUB}
                FROM expeditions e
                LEFT JOIN expedition_counties ec ON e.id = ec.expedition_id
                WHERE e.date_start <= ?
                GROUP BY e.id ORDER BY COALESCE(e.date_end, e.date_start) DESC LIMIT {PAGE+1} OFFSET {offset}
            """, (date_to,)).fetchall()
        else:
            rows = []
    has_more = len(rows) > PAGE
    return templates.TemplateResponse("_results.html", {
        "request": request, "items": _enrich(rows[:PAGE]), "has_more": has_more,
    })


@router.get("/fragment/search", response_class=HTMLResponse)
def fragment_search(request: Request, q: str = Query(""), offset: int = Query(0)):
    rows = []
    if q:
        pattern = f"%{q}%"
        with get_conn() as conn:
            rows = conn.execute(f"""
                SELECT e.*, GROUP_CONCAT(DISTINCT ec.county) as all_counties, {_LEADER_SUB}
                FROM expeditions e
                LEFT JOIN expedition_counties ec ON e.id = ec.expedition_id
                WHERE e.name LIKE ? OR e.region LIKE ? OR e.county LIKE ? OR e.description LIKE ?
                GROUP BY e.id ORDER BY COALESCE(e.date_end, e.date_start) DESC LIMIT {PAGE+1} OFFSET {offset}
            """, (pattern, pattern, pattern, pattern)).fetchall()
    has_more = len(rows) > PAGE
    return templates.TemplateResponse("_results.html", {
        "request": request, "items": _enrich(rows[:PAGE]), "has_more": has_more,
    })


# ── Detail pages ───────────────────────────────────────────────────────────

@router.get("/region/{county}", response_class=HTMLResponse)
def county_detail(request: Request, county: str):
    with get_conn() as conn:
        rows = conn.execute(
            "SELECT DISTINCT region FROM expeditions WHERE county = ? ORDER BY region",
            (county,)
        ).fetchall()
    return templates.TemplateResponse("region.html", {
        "request": request, "county": county, "regions": rows,
    })


@router.get("/region/{county}/{region}", response_class=HTMLResponse)
def region_detail(request: Request, county: str, region: str):
    with get_conn() as conn:
        rows = conn.execute(
            "SELECT * FROM expeditions WHERE county = ? AND region = ? ORDER BY date_start DESC",
            (county, region)
        ).fetchall()
    return templates.TemplateResponse("expedition_list.html", {
        "request": request, "county": county, "region": region, "expeditions": rows,
    })
