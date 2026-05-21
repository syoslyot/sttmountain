from fastapi import APIRouter, Request, Query
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from pathlib import Path
from app.models import supabase

router = APIRouter()
templates = Jinja2Templates(directory=Path(__file__).parent.parent / "templates")


@router.get("/search", response_class=HTMLResponse)
def search(request: Request, q: str = Query("")):
    expeditions = []
    if q:
        result = supabase.rpc("list_expeditions", {"p_q": q, "p_page_size": 200}).execute()
        expeditions = (result.data or {}).get("expeditions") or []
    return templates.TemplateResponse("search.html", {
        "request": request, "expeditions": expeditions, "q": q,
    })
