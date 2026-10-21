import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pymongo.errors import PyMongoError
from app.routes import usuario_routes
from app.routes.dashboard_route import (
    relatorio_consolidado,
    resumo_operacional,
    router as dashboard_router,
    upload_lote_e_gerar_relatorio,
)
from app.routes.transporte_route import (
    processar_e_salvar_html,
    router as transporte_router,
)
from app.schemas.dashboard_schema import (
    RelatorioConsolidadoSchema,
    RelatorioUploadIntegradoSchema,
    ResumoOperacionalSchema,
)
from app.schemas.transporte_schema import RespostaProcessamentoEPersistenciaSchema
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

app.add_api_route(
    "/api/v1/relatorios/upload",
    processar_e_salvar_html,
    methods=["POST"],
    response_model=RespostaProcessamentoEPersistenciaSchema,
    tags=["Transporte"],
)
app.add_api_route(
    "/api/v1/dashboard/metricas",
    resumo_operacional,
    methods=["GET"],
    response_model=ResumoOperacionalSchema,
    tags=["Dashboard"],
)
app.add_api_route(
    "/api/v1/dashboard/relatorio",
    relatorio_consolidado,
    methods=["GET"],
    name="relatorio_consolidado_v1_get",
    response_model=RelatorioConsolidadoSchema,
    tags=["Dashboard"],
)
app.add_api_route(
    "/api/v1/dashboard/relatorio",
    relatorio_consolidado,
    methods=["POST"],
    name="relatorio_consolidado_v1_post",
    response_model=RelatorioConsolidadoSchema,
    tags=["Dashboard"],
)
app.add_api_route(
    "/api/v1/dashboard/relatorio/upload-e-gerar",
    upload_lote_e_gerar_relatorio,
    methods=["POST"],
    name="upload_lote_e_gerar_relatorio_v1",
    response_model=RelatorioUploadIntegradoSchema,
    tags=["Dashboard"],
)

@app.get("/")
def status_check():
    return {"status": "Servidor rodando", "projeto": "semob_dashboard"}