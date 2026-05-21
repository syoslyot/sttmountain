import calendar
from fastapi import APIRouter, Request, Query
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from pathlib import Path
from app.models import supabase

router = APIRouter()
templates = Jinja2Templates(directory=Path(__file__).parent.parent / "templates")


@router.get("/date", response_class=HTMLResponse)
def by_date(request: Request, year: int | None = Query(None), month: int | None = Query(None)):
    params: dict = {"p_page_size": 500}
    if year and month:
        last_day = calendar.monthrange(year, month)[1]
        params["p_start"] = f"{year}-{month:02d}-01"
        params["p_end"]   = f"{year}-{month:02d}-{last_day:02d}"
    elif year:
        params["p_start"] = f"{year}-01-01"
        params["p_end"]   = f"{year}-12-31"
    result = supabase.rpc("list_expeditions", params).execute()
    expeditions = (result.data or {}).get("expeditions") or []
    return templates.TemplateResponse("date.html", {
        "request": request, "expeditions": expeditions, "year": year, "month": month,
    })
