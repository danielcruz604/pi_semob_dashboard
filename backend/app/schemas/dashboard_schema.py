from typing import Any, Dict, List, Optional
from pydantic import BaseModel

class PeriodoFiltroSchema(BaseModel):
    data_inicio: Optional[str] = None
    data_fim: Optional[str] = None
    agrupamento: Optional[str] = None
    linha: Optional[str] = None

class FiltrosDisponiveisSchema(BaseModel):
    data_minima: Optional[str] = None
    data_maxima: Optional[str] = None
    linhas: List[str]
    agrupamentos: List[str]
    classificacoes_ocorrencia: List[str]

class QuilometragemKpiSchema(BaseModel):
    km_total: float
    km_produtivo: float
    km_improdutivo: float
    taxa_improdutiva_percentual: float
    media_diaria_km: float

class TurnoFcvKpiSchema(BaseModel):
    prog: int
    real: int
    fcv: float


class ViagensKpiSchema(BaseModel):
    programadas: int
    realizadas: int
    diferenca: int
    fcv_medio: float
    por_periodo: Dict[str, TurnoFcvKpiSchema]

class PassageirosKpiSchema(BaseModel):
    pagantes: int
    catraca: int
    antecipados: int
    nao_pagantes: int
    total_geral: int
    percentual_gratuidade: float

class FinanceiroKpiSchema(BaseModel):
    total_vendas: float
    total_utilizacao: float
    creditos_transferidos_cartoes: float
    credito_circulante_acumulado: float
    saldo_final_recente: Optional[float] = None
    receita_por_km: float

class ResumoOperacionalSchema(BaseModel):
    periodo: PeriodoFiltroSchema
    quilometragem: QuilometragemKpiSchema
    viagens: ViagensKpiSchema
    passageiros: PassageirosKpiSchema
    financeiro: FinanceiroKpiSchema

class ItemSerieTemporalSchema(BaseModel):
    referencia: str
    numero_veiculos: int = 0
    numero_max_veiculos_faixa: int = 0
    km_total: float
    km_produtivo: float
    km_improdutivo: float
    viagens_programadas: int
    viagens_realizadas: int
    fcv: float
    fcv_por_periodo: Optional[Dict[str, TurnoFcvKpiSchema]] = None
    passageiros_pagantes: int
    catraca: int = 0
    antecipados: int = 0
    passageiros_nao_pagantes: int
    total_passageiros: int
    total_vendas: float
    total_utilizacao: float
    credito_circulante: float
    receita_por_km: float

class SerieTemporalResponseSchema(BaseModel):
    periodo: PeriodoFiltroSchema
    total_pontos: int
    serie: List[ItemSerieTemporalSchema]

class LinhaRankingSchema(BaseModel):
    linha: str
    km_total: float
    viagens: int
    media_km_por_viagem: float
    participacao_km_percentual: float

class HorarioLinhaSchema(BaseModel):
    data: str
    linha: str
    hora: int
    numero_veiculos: Optional[int] = None
    viagens: Optional[int] = None
    partidas: List[int]

class EstatisticasHistoricasSchema(BaseModel):
    media_km: float
    desvio_padrao_km: float
    media_viagens_realizadas: float
    desvio_padrao_viagens: float
    media_fcv: float
    desvio_padrao_fcv: float
    media_tarifa_efetiva: float
    desvio_padrao_tarifa_efetiva: float

class DesvioOperacionalSchema(BaseModel):
    data: str
    tipo: str
    indicador: str
    valor_observado: float
    valor_referencia: float
    desvio_padrao_referencia: Optional[float] = None
    z_score: Optional[float] = None
    desvio_percentual: Optional[float] = None
    descricao: str

class AnomaliasResponseSchema(BaseModel):
    periodo: PeriodoFiltroSchema
    parametros_tolerancia: Dict[str, float]
    estatisticas_historicas: EstatisticasHistoricasSchema
    total_ocorrencias_viagens: int
    ocorrencias_por_classificacao: Dict[str, int]
    ocorrencias: List[Dict[str, Any]]
    total_desvios_operacionais: int
    desvios_operacionais: List[DesvioOperacionalSchema]

class RelatorioConsolidadoSchema(BaseModel):
    gerado_em: str
    periodo: PeriodoFiltroSchema
    resumo_operacional: ResumoOperacionalSchema
    estatisticas_historicas: EstatisticasHistoricasSchema
    serie_temporal: SerieTemporalResponseSchema
    ranking_linhas: List[LinhaRankingSchema]
    anomalias: AnomaliasResponseSchema

class ResultadoArquivoLoteSchema(BaseModel):
    arquivo: str
    status: str
    tipo_relatorio: Optional[str] = None
    colecao: Optional[str] = None
    total_registros_validos: int = 0
    documentos_afetados: Optional[int] = None
    detalhe_erro: Optional[str] = None

class RelatorioUploadIntegradoSchema(BaseModel):
    total_arquivos_recebidos: int
    total_arquivos_persistidos: int
    total_arquivos_apenas_processados: int
    total_arquivos_com_erro: int
    arquivos: List[ResultadoArquivoLoteSchema]
    relatorio: RelatorioConsolidadoSchema