from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.routes import usuario_routes

app = FastAPI(
    title="Semob Dashboard API",
    description="API multiplataforma para gestão e visualização de métricas de mobilidade",
    version="1.0.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(usuario_routes.router)

@app.get("/")
def status_check():
    return {"status": "Servidor rodando", "projeto": "semob_dashboard"}
