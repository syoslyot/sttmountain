from fastapi import APIRouter, Request, Query
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from pathlib import Path
from app.models import supabase

router = APIRouter()
templates = Jinja2Templates(directory=Path(__file__).parent.parent / "templates")

PAGE = 20

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


def _enrich(rows: list[dict]) -> list[dict]:
    for d in rows:
        entry_county = d.get("region_entry_county") or ""
        entry_town   = d.get("region_entry_town") or ""
        exit_county  = d.get("region_exit_county") or ""
        exit_town    = d.get("region_exit_town") or ""
        parts = []
        if entry_county:
            parts.append(f"{entry_county} · {entry_town}" if entry_town else entry_county)
        if exit_county and exit_county != entry_county:
            parts.append(f"{exit_county} · {exit_town}" if exit_town else exit_county)
        d["counties_display"] = " / ".join(parts)
        d["leader_name"] = d.get("leader") or ""
    return rows


def _list_expeditions(offset: int = 0, **kwargs) -> tuple[list[dict], bool]:
    page = offset // PAGE + 1
    result = supabase.rpc("list_expeditions", {"p_page": page, "p_page_size": PAGE, **kwargs}).execute()
    data = result.data or {}
    items = data.get("expeditions") or []
    total = data.get("total", 0)
    return items, total > offset + len(items)


@router.get("/", response_class=HTMLResponse)
def home(request: Request, mode: str = "map"):
    result = supabase.rpc("get_expedition_dates", {}).execute()
    date_min = (result.data or {}).get("min_date") or ""
    date_max = (result.data or {}).get("max_date") or ""
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
    items, has_more = _list_expeditions(offset)
    return templates.TemplateResponse("_results.html", {
        "request": request, "items": _enrich(items), "has_more": has_more,
    })


@router.get("/fragment/county/{name}", response_class=HTMLResponse)
def fragment_county(request: Request, name: str, offset: int = Query(0)):
    items, has_more = _list_expeditions(offset, p_county=name)
    return templates.TemplateResponse("_results.html", {
        "request": request, "items": _enrich(items), "has_more": has_more,
    })


@router.get("/fragment/date", response_class=HTMLResponse)
def fragment_date(
    request: Request,
    date_from: str | None = Query(None),
    date_to: str | None = Query(None),
    offset: int = Query(0),
):
    kwargs: dict = {}
    if date_from:
        kwargs["p_start"] = date_from
    if date_to:
        kwargs["p_end"] = date_to
    if not kwargs:
        return templates.TemplateResponse("_results.html", {
            "request": request, "items": [], "has_more": False,
        })
    items, has_more = _list_expeditions(offset, **kwargs)
    return templates.TemplateResponse("_results.html", {
        "request": request, "items": _enrich(items), "has_more": has_more,
    })


@router.get("/fragment/search", response_class=HTMLResponse)
def fragment_search(request: Request, q: str = Query(""), offset: int = Query(0)):
    if not q:
        return templates.TemplateResponse("_results.html", {
            "request": request, "items": [], "has_more": False,
        })
    items, has_more = _list_expeditions(offset, p_q=q)
    return templates.TemplateResponse("_results.html", {
        "request": request, "items": _enrich(items), "has_more": has_more,
    })


# ── Detail pages ───────────────────────────────────────────────────────────

@router.get("/region/{county}", response_class=HTMLResponse)
def county_detail(request: Request, county: str):
    rows = (
        supabase.table("expeditions")
        .select("region_entry_town")
        .eq("region_entry_county", county)
        .execute()
        .data or []
    )
    towns = sorted({r["region_entry_town"] for r in rows if r.get("region_entry_town")})
    return templates.TemplateResponse("region.html", {
        "request": request,
        "county": county,
        "regions": [{"region": t} for t in towns],
    })


@router.get("/region/{county}/{region}", response_class=HTMLResponse)
def region_detail(request: Request, county: str, region: str):
    rows = (
        supabase.table("expeditions")
        .select("*")
        .eq("region_entry_county", county)
        .eq("region_entry_town", region)
        .order("date_start", desc=True)
        .execute()
        .data or []
    )
    return templates.TemplateResponse("expedition_list.html", {
        "request": request, "county": county, "region": region, "expeditions": rows,
    })
