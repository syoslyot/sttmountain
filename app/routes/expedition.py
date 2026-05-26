from fastapi import APIRouter, Request, HTTPException
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from pathlib import Path
from app.models import supabase, STORAGE_BASE

router = APIRouter()
templates = Jinja2Templates(directory=Path(__file__).parent.parent / "templates")


@router.get("/expedition/{expedition_id}", response_class=HTMLResponse)
def expedition_detail(request: Request, expedition_id: int):
    exp_res = (
        supabase.table("expeditions")
        .select("*")
        .eq("id", expedition_id)
        .eq("is_public", True)
        .execute()
    )
    if not exp_res.data:
        raise HTTPException(status_code=404)
    exp = exp_res.data[0]
    gpx_files = supabase.table("gpx_files").select("*").eq("expedition_id", expedition_id).execute().data or []
    map_files  = supabase.table("map_files").select("*").eq("expedition_id", expedition_id).execute().data or []
    records    = supabase.table("records").select("*").eq("expedition_id", expedition_id).execute().data or []
    return templates.TemplateResponse("expedition.html", {
        "request":      request,
        "exp":          exp,
        "gpx_files":    gpx_files,
        "map_files":    map_files,
        "records":      records,
        "storage_base": STORAGE_BASE,
    })
