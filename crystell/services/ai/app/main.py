import os

from fastapi import FastAPI, HTTPException

app = FastAPI(
    title="Crystell AI Service",
    version="0.1.0",
    docs_url="/docs",
    redoc_url=None,
)


@app.get("/health", tags=["system"])
def health() -> dict[str, str]:
    return {"status": "ok", "service": "crystell-ai"}


@app.get("/ready", tags=["system"])
def ready() -> dict[str, str]:
    token = os.getenv("AI_INTERNAL_TOKEN", "")
    if not token:
        raise HTTPException(status_code=503, detail="AI service is not configured")

    return {"status": "ready", "service": "crystell-ai"}
