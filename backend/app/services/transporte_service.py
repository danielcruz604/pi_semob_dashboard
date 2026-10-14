import json
import logging
import re
from typing import Any, Dict, List, Optional, Tuple
import pandas as pd
from pymongo.database import Database
from app.services.transporte_cleaner import higienizar_dataframe
from app.services.transporte_mapper import (
    mapear_financeiro_sistema,
    mapear_passageiros_sistema,
    mapear_viagens_horario,
    mapear_viagens_linhas,
    mapear_viagens_ocorrencias,
    mapear_viagens_sistema,
)
from app.services.transporte_metadata import extrair_metadados_nome_arquivo
from app.services.transporte_repository import (
    COL_FINANCEIRO_SISTEMA,
    COL_PASSAGEIROS_SISTEMA,
    COL_VIAGENS_HORARIO,
    COL_VIAGENS_LINHAS,
    COL_VIAGENS_OCORRENCIAS,
    COL_VIAGENS_SISTEMA,
    upsert_financeiro_sistema,
    upsert_passageiros_sistema,
    upsert_viagens_horario,
    upsert_viagens_linhas,
    upsert_viagens_ocorrencias,
    upsert_viagens_sistema,
)
from app.services.transporte_tables import ler_tabelas_html

logger = logging.getLogger(__name__)

def _nome_conjunto_dados(tipo_relatorio: str, df: pd.DataFrame, indice: int) -> str:
    colunas = set(df.columns)
    if {"creditos_transferidos_para_cartoes", "saldo_final"}.intersection(colunas):
        return "saldos_creditos"
    if {"total_vendas", "total_utilizacao", "credito_circulante"}.intersection(colunas):
        return "saldos_movimentacoes"
    if {"catraca", "total_passageiros", "nao_pagantes"}.intersection(colunas):
        return "passageiros"
    base = re.sub(r"_+", "_", tipo_relatorio).strip("_") or "transporte"
    return base if indice == 1 else f"{base}_tabela_{indice}"

def _converter_para_registros(df: pd.DataFrame) -> List[Dict[str, Any]]:
    if df.empty:
        return []
    return json.loads(
        df.to_json(orient="records", date_format="iso", force_ascii=False, double_precision=15)
    )

def _atualizar_intervalo_datas(metadados: Dict[str, Any], dataframes: List[pd.DataFrame]) -> None:
    series = [
        pd.to_datetime(df["data"], errors="coerce")
        for df in dataframes
        if "data" in df.columns and not df.empty
    ]
    if not series:
        return
    datas = pd.concat(series).dropna()
    if not datas.empty:
        metadados["data_inicio"] = datas.min().strftime("%Y-%m-%d")
        metadados["data_fim"] = datas.max().strftime("%Y-%m-%d")

def _construir_conjuntos(
    conteudo_bytes: bytes, nome_arquivo: str
) -> Tuple[Dict[str, Any], List[Dict[str, Any]]]:
    tabelas = ler_tabelas_html(conteudo_bytes)
    metadados = extrair_metadados_nome_arquivo(nome_arquivo)
    dataframes = [higienizar_dataframe(tabela, metadados) for tabela in tabelas]
    if not dataframes:
        raise ValueError("Nenhuma tabela pôde ser processada.")
    _atualizar_intervalo_datas(metadados, dataframes)

    conjuntos: List[Dict[str, Any]] = []
    nomes_usados = set()
    for indice, df in enumerate(dataframes, start=1):
        nome = _nome_conjunto_dados(metadados["tipo_relatorio"], df, indice)
        if nome in nomes_usados:
            nome = f"{nome}_{indice}"
        nomes_usados.add(nome)
        registros = _converter_para_registros(df)
        conjuntos.append({
            "nome": nome,
            "colunas": list(df.columns),
            "total_registros_validos": len(registros),
            "dados": registros,
        })
    return metadados, conjuntos

def _montar_resposta(
    nome_arquivo: str, metadados: Dict[str, Any], conjuntos: List[Dict[str, Any]]
) -> Dict[str, Any]:
    principal = conjuntos[0]
    resultado: Dict[str, Any] = {
        "arquivo": nome_arquivo,
        "metadados": metadados,
        "total_registros_validos": principal["total_registros_validos"],
        "colunas": principal["colunas"],
        "dados": principal["dados"],
    }
    if len(conjuntos) > 1:
        resultado["conjuntos_dados"] = conjuntos
        resultado["total_registros_conjuntos"] = sum(
            c["total_registros_validos"] for c in conjuntos
        )
    return resultado

def processar_html_bytes(conteudo_bytes: bytes, nome_arquivo: str) -> Dict[str, Any]:
    metadados, conjuntos = _construir_conjuntos(conteudo_bytes, nome_arquivo)
    return _montar_resposta(nome_arquivo, metadados, conjuntos)

_PERIODOS = {"mensal", "quinzenal", "semanal", "diario", "diaria"}
_OCORRENCIAS = {"ninic": "NaoIniciada", "nrealiz": "NaoRealizada", "nterm": "NaoTerminada"}

def _classificar_relatorio(tipo: str) -> str:
    #Classifica pelo conjunto de palavras do tipo (e não por substring)
    partes = set(tipo.split("_"))
    if partes & {"saldo", "saldos"}:
        return "saldos"
    if "passageiros" in partes:
        return "passageiros"
    if "linhas" in partes:
        return "linhas"
    if "fxhr" in partes:
        return "resumo_fxhr" if "resumo" in partes else "fxhr"
    if "viag" in partes and partes & set(_OCORRENCIAS):
        return "ocorrencias"
    if "viagens" in partes:
        return "viagens_detalhe"
    if partes & _PERIODOS and not (partes - _PERIODOS - {"fcv"}):
        return "resumo_geral"
    return "desconhecido"

_SEM_COLECAO = {
    "resumo_fxhr": "resumo por faixa horária (sem coleção de destino definida)",
    "viagens_detalhe": "viagens detalhadas por trecho (sem coleção de destino definida)",
}

def _persistir(
    db: Database, tipo: str, conjuntos: List[Dict[str, Any]]
) -> Tuple[str, int, Optional[int]]:
    #Despacha para o mapper/repositório corretos. Retorna (coleção, afetados, descartados).
    categoria = _classificar_relatorio(tipo)
    dados = conjuntos[0]["dados"]

    if categoria in _SEM_COLECAO:
        raise ValueError(
            f"Relatório '{tipo}' reconhecido como {_SEM_COLECAO[categoria]}; "
            "use /processar-html para apenas processá-lo."
        )

    if categoria == "saldos":
        creditos = movimentacoes = None
        for c in conjuntos:
            if c["nome"].startswith("saldos_creditos"):
                creditos = c["dados"]
            elif c["nome"].startswith("saldos_movimentacoes"):
                movimentacoes = c["dados"]
        if creditos is None and movimentacoes is None:
            raise ValueError("Relatório de saldos sem tabelas de créditos ou movimentações reconhecidas.")
        docs = mapear_financeiro_sistema(creditos, movimentacoes)
        return COL_FINANCEIRO_SISTEMA, upsert_financeiro_sistema(db, docs), None

    if categoria == "passageiros":
        docs = mapear_passageiros_sistema(dados)
        return COL_PASSAGEIROS_SISTEMA, upsert_passageiros_sistema(db, docs), len(dados) - len(docs)

    if categoria == "linhas":
        docs = mapear_viagens_linhas(dados)
        return COL_VIAGENS_LINHAS, upsert_viagens_linhas(db, docs), len(dados) - len(docs)

    if categoria == "fxhr":
        docs = mapear_viagens_horario(dados)
        return COL_VIAGENS_HORARIO, upsert_viagens_horario(db, docs), len(dados) - len(docs)

    if categoria == "ocorrencias":
        classificacao = next(v for k, v in _OCORRENCIAS.items() if k in tipo.split("_"))
        docs = mapear_viagens_ocorrencias(dados, classificacao_padrao=classificacao)
        return COL_VIAGENS_OCORRENCIAS, upsert_viagens_ocorrencias(db, docs), len(dados) - len(docs)

    if categoria == "resumo_geral":
        #Resumo (Mensal/Quinzenal) e FCV usam o mesmo mapper; cada arquivo atualiza só os campos que possui.
        docs = mapear_viagens_sistema(dados)
        return COL_VIAGENS_SISTEMA, upsert_viagens_sistema(db, docs), len(dados) - len(docs)

    raise ValueError(f"Tipo de relatório '{tipo}' não possui mapeamento de persistência.")

def processar_e_persistir_html_bytes(
    conteudo_bytes: bytes, nome_arquivo: str, db: Optional[Database] = None
) -> Dict[str, Any]:
    #Processa o HTML e persiste no MongoDB. `db` pode ser injetado (testes).
    metadados, conjuntos = _construir_conjuntos(conteudo_bytes, nome_arquivo)
    resultado = _montar_resposta(nome_arquivo, metadados, conjuntos)

    if db is None:
        from app.utils.connection_factory import ConnectionFactory  # import tardio: desacopla testes unitários
        db = ConnectionFactory().db

    colecao, afetados, descartados = _persistir(db, metadados["tipo_relatorio"], conjuntos)
    if descartados:
        logger.warning("%s: %d registros descartados (chave/data inválida).", nome_arquivo, descartados)

    resultado["persistencia"] = {
        "colecao": colecao,
        "documentos_afetados": afetados,
        "registros_descartados": descartados,
    }
    return resultado