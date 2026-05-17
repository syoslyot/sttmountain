from fastapi import APIRouter, Request, HTTPException
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from pathlib import Path
from app.models import get_conn

router = APIRouter()
templates = Jinja2Templates(directory=Path(__file__).parent.parent / "templates")

@router.get("/expedition/{expedition_id}", response_class=HTMLResponse)
def expedition_detail(request: Request, expedition_id: int):
    with get_conn() as conn:
        exp = conn.execute("SELECT * FROM expeditions WHERE id = ?", (expedition_id,)).fetchone()
        if not exp:
            raise HTTPException(status_code=404)
        gpx_files = conn.execute("SELECT * FROM gpx_files WHERE expedition_id = ?", (expedition_id,)).fetchall()
        map_files = conn.execute("SELECT * FROM map_files WHERE expedition_id = ?", (expedition_id,)).fetchall()
        records   = conn.execute("SELECT * FROM records   WHERE expedition_id = ?", (expedition_id,)).fetchall()
    return templates.TemplateResponse("expedition.html", {
        "request":   request,
        "exp":       exp,
        "gpx_files": gpx_files,
        "map_files": map_files,
        "records":   records,
    })
