from fastapi import FastAPI

app = FastAPI(
    title="Crystell AI Service",
    version="0.1.0",
    docs_url="/docs",
    redoc_url=None,
)


@app.get("/health", tags=["system"])
def health() -> dict[str, str]:
    return {"status": "ok", "service": "crystell-ai"}
