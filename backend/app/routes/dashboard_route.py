import logging
from typing import List, Optional
from fastapi import APIRouter, HTTPException, Query
from pymongo.errors import PyMongoError
from app.schemas.dashboard_schema import (
    AnomaliasResponseSchema,
    FiltrosDisponiveisSchema,
    HorarioLinhaSchema,
    LinhaRankingSchema,
    RelatorioConsolidadoSchema,
    ResumoOperacionalSchema,
    SerieTemporalResponseSchema,
)
from app.services.dashboard_service import (
    gerar_relatorio_operacional,
    obter_anomalias,
    obter_filtros_disponiveis,
    obter_horarios_linhas,
    obter_ranking_linhas,
    obter_resumo_dashboard,
    obter_serie_temporal,
)
from app.utils.connection_factory import ConnectionFactory

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/dashboard", tags=["Dashboard"])

def _executar_consulta(funcao, *args, **kwargs):
    try:
        db = ConnectionFactory().db
        return funcao(db, *args, **kwargs)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except RuntimeError as exc:
        logger.exception("Erro de configuração do banco")
        raise HTTPException(status_code=503, detail="Banco de dados não configurado.") from exc
    except PyMongoError as exc:
        logger.exception("Falha ao consultar o MongoDB")
        raise HTTPException(status_code=503, detail="Falha ao acessar o banco de dados.") from exc


@router.get("/filtros", response_model=FiltrosDisponiveisSchema)
def listar_filtros_disponiveis():
    return _executar_consulta(obter_filtros_disponiveis)

@router.get("/resumo-operacional", response_model=ResumoOperacionalSchema)
def resumo_operacional(
    data_inicio: Optional[str] = Query(None, description="Data inicial (YYYY-MM-DD)"),
    data_fim: Optional[str] = Query(None, description="Data final (YYYY-MM-DD)"),
    linha: Optional[str] = Query(None, description="Código da linha de ônibus (opcional)"),
):
    return _executar_consulta(
        obter_resumo_dashboard, data_inicio=data_inicio, data_fim=data_fim, linha=linha
    )

@router.get("/serie-temporal", response_model=SerieTemporalResponseSchema)
def serie_temporal(
    agrupamento: str = Query("diario", description="diario, semanal ou mensal"),
    data_inicio: Optional[str] = Query(None, description="Data inicial (YYYY-MM-DD)"),
    data_fim: Optional[str] = Query(None, description="Data final (YYYY-MM-DD)"),
    linha: Optional[str] = Query(None, description="Código da linha de ônibus (opcional)"),
):
    return _executar_consulta(
        obter_serie_temporal,
        agrupamento=agrupamento,
        data_inicio=data_inicio,
        data_fim=data_fim,
        linha=linha,
    )

@router.get("/linhas-ranking", response_model=List[LinhaRankingSchema])
def linhas_ranking(
    data_inicio: Optional[str] = Query(None, description="Data inicial (YYYY-MM-DD)"),
    data_fim: Optional[str] = Query(None, description="Data final (YYYY-MM-DD)"),
    linha: Optional[str] = Query(None, description="Código da linha (ex.: 01)"),
):
    return _executar_consulta(
        obter_ranking_linhas, data_inicio=data_inicio, data_fim=data_fim, linha=linha
    )

@router.get("/horarios", response_model=List[HorarioLinhaSchema])
def horarios_linhas(
    data_inicio: Optional[str] = Query(None, description="Data inicial (YYYY-MM-DD)"),
    data_fim: Optional[str] = Query(None, description="Data final (YYYY-MM-DD)"),
    linha: Optional[str] = Query(None, description="Código da linha (ex.: 01)"),
):
    return _executar_consulta(
        obter_horarios_linhas, data_inicio=data_inicio, data_fim=data_fim, linha=linha
    )

@router.get("/anomalias", response_model=AnomaliasResponseSchema)
def anomalias_operacionais(
    data_inicio: Optional[str] = Query(None, description="Data inicial (YYYY-MM-DD)"),
    data_fim: Optional[str] = Query(None, description="Data final (YYYY-MM-DD)"),
    linha: Optional[str] = Query(None, description="Código da linha (ex.: 01)"),
    classificacao: Optional[str] = Query(None, description="NaoIniciada, NaoRealizada ou NaoTerminada"),
    tolerancia_desvio_km_pct: float = Query(15.0, ge=0.0, description="Tolerância (%) de desvio da média de km"),
    limiar_fcv: float = Query(0.98, ge=0.0, le=1.0, description="Alerta para FCV abaixo deste valor"),
    limiar_km_improd_pct: float = Query(10.0, ge=0.0, description="Alerta para % de km improdutivo acima deste valor"),
):
    return _executar_consulta(
        obter_anomalias,
        data_inicio=data_inicio,
        data_fim=data_fim,
        linha=linha,
        classificacao=classificacao,
        tolerancia_desvio_km_pct=tolerancia_desvio_km_pct,
        limiar_fcv=limiar_fcv,
        limiar_km_improd_pct=limiar_km_improd_pct,
    )

@router.get("/relatorio", response_model=RelatorioConsolidadoSchema)
@router.post("/relatorio/gerar", response_model=RelatorioConsolidadoSchema)
def relatorio_consolidado(
    agrupamento: str = Query("diario", description="diario, semanal ou mensal"),
    data_inicio: Optional[str] = Query(None, description="Data inicial (YYYY-MM-DD)"),
    data_fim: Optional[str] = Query(None, description="Data final (YYYY-MM-DD)"),
    linha: Optional[str] = Query(None, description="Código da linha (ex.: 01)"),
    tolerancia_desvio_km_pct: float = Query(15.0, ge=0.0, description="Tolerância (%) de desvio da média de km"),
    limiar_fcv: float = Query(0.98, ge=0.0, le=1.0, description="Alerta para FCV abaixo deste valor"),
    limiar_km_improd_pct: float = Query(10.0, ge=0.0, description="Alerta para % de km improdutivo acima deste valor"),
):
    return _executar_consulta(
        gerar_relatorio_operacional,
        agrupamento=agrupamento,
        data_inicio=data_inicio,
        data_fim=data_fim,
        linha=linha,
        tolerancia_desvio_km_pct=tolerancia_desvio_km_pct,
        limiar_fcv=limiar_fcv,
        limiar_km_improd_pct=limiar_km_improd_pct,
    )