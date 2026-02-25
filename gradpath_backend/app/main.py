from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.routes import router as api_router
from app.core.database import engine
from app.models.base import Base
import app.models  # noqa: F401

app = FastAPI(title="GradPath API", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(api_router)


@app.on_event("startup")
def on_startup():
    Base.metadata.create_all(bind=engine)
    # Additive column migrations — safe to run repeatedly
    with engine.connect() as conn:
        from sqlalchemy import text
        for stmt in [
            "ALTER TABLE plan_items ADD COLUMN IF NOT EXISTS credits INTEGER",
        ]:
            try:
                conn.execute(text(stmt))
                conn.commit()
            except Exception:
                pass


@app.get("/health")
def health_check():
    return {"status": "ok"}
