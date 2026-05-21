from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from pathlib import Path

from app.routes import region, date, search, expedition


app = FastAPI(title="sttmount")

app.mount("/static", StaticFiles(directory=Path(__file__).parent / "static"), name="static")

templates = Jinja2Templates(directory=Path(__file__).parent / "templates")

app.include_router(region.router)
app.include_router(date.router)
app.include_router(search.router)
app.include_router(expedition.router)
