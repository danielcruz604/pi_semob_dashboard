import json
import re
from typing import Any, Dict, List
import pandas as pd
from app.services.transporte_cleaner import higienizar_dataframe
from app.services.transporte_columns import normalizar_nome_coluna
from app.services.transporte_metadata import extrair_metadados_nome_arquivo
from app.services.transporte_tables import ler_tabelas_html

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
    json_texto = df.to_json(
        orient="records",
        date_format="iso",
        force_ascii=False,
        double_precision=15,
    )
    return json.loads(json_texto)

def _atualizar_intervalo_datas(metadados: Dict[str, Any], dataframes: List[pd.DataFrame]) -> None:
    datas = []
    for df in dataframes:
        if "data" not in df.columns or df.empty:
            continue
        serie = pd.to_datetime(df["data"], errors="coerce")
        datas.extend(serie.dropna().dt.strftime("%Y-%m-%d").tolist())
    if datas:
        metadados["data_inicio"] = min(datas)
        metadados["data_fim"] = max(datas)

def processar_html_bytes(conteudo_bytes: bytes, nome_arquivo: str) -> Dict[str, Any]:
    tabelas = ler_tabelas_html(conteudo_bytes)
    metadados = extrair_metadados_nome_arquivo(nome_arquivo)

    dataframes = [
        higienizar_dataframe(tabela, metadados)
        for tabela in tabelas
    ]
    _atualizar_intervalo_datas(metadados, dataframes)

    conjuntos = []
    nomes_usados = set()
    for indice, df in enumerate(dataframes, start=1):
        nome = _nome_conjunto_dados(
            metadados["tipo_relatorio"],
            df,
            indice,
        )
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

    conjunto_principal = conjuntos[0]
    resultado = {
        "arquivo": nome_arquivo,
        "metadados": metadados,
        "total_registros_validos": conjunto_principal["total_registros_validos"],
        "colunas": conjunto_principal["colunas"],
        "dados": conjunto_principal["dados"],
    }

    if len(conjuntos) > 1:
        resultado["conjuntos_dados"] = conjuntos
        resultado["total_registros_conjuntos"] = sum(
            conjunto["total_registros_validos"] for conjunto in conjuntos
        )

    return resultado