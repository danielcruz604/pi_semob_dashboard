import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI
from pymongo.errors import PyMongoError
from app.routes.transporte_route import router as transporte_router
from app.services.transporte_repository import garantir_indices
from app.utils.connection_factory import ConnectionFactory

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
app.include_router(transporte_router, prefix="/api")