from fastapi import FastAPI
from app.routes import usuario_routes

app = FastAPI(
    title="Semob Dashboard API",
    description="API multiplataforma para gestão e visualização de métricas de mobilidade",
    version="1.0.0"
)

app.include_router(usuario_routes.router)

@app.get("/")
def status_check():
    return {"status": "Servidor rodando", "projeto": "semob_dashboard"}
