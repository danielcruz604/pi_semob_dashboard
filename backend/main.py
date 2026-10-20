import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI
from pymongo.errors import PyMongoError
from app.routes.transporte_route import router as transporte_router
from app.services.transporte_repository import garantir_indices
from app.utils.connection_factory import ConnectionFactory
from app.routes.dashboard_route import router as dashboard_router
from fastapi.middleware.cors import CORSMiddleware
from app.routes import usuario_routes

logger = logging.getLogger(__name__)

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Índices únicos tornam os upserts idempotentes mesmo com requisições concorrentes.
    try:
        garantir_indices(ConnectionFactory().db)
    except (PyMongoError, RuntimeError):
        logger.exception("Não foi possível garantir os índices do MongoDB no startup.")
    yield
    ConnectionFactory().close()

app = FastAPI(title="API de Transporte Municipal", version="1.0.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(transporte_router, prefix="/api")
app.include_router(dashboard_router, prefix="/api")

app.include_router(usuario_routes.router, prefix="/api")

@app.get("/")
def status_check():
    return {"status": "Servidor rodando", "projeto": "semob_dashboard"}