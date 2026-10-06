from fastapi import FastAPI
from app.routes.transporte_route import router as transporte_router

app = FastAPI(
    title="API de Transporte Municipal",
    version="1.0.0"
)

app.include_router(transporte_router, prefix="/api")