import re
from typing import Any, Dict
import pandas as pd
from app.services.transporte_columns import (
    COLUNAS_DECIMAIS,
    COLUNAS_INTEIRAS,
    desduplicar_colunas,
    nome_coluna_base,
    normalizar_nome_coluna,
    normalizar_texto,
)
from app.services.transporte_numbers import tentar_converter_coluna_numerica

COLUNAS_DATA_HORA = {
    "inicio_programado", "inicio_realizado", "fim_programado", "fim_realizado",
}

MARCADORES_AGREGADOS = re.compile(
    r"^(?:total(?:\s|_|$)|subtotal(?:\s|_|$)|resumo(?:\s|_|$)|fonte:|emissao:|pagina:)"
)

def _adicionar_metadados(df: pd.DataFrame, metadados: Dict[str, Any]) -> pd.DataFrame:
    df["meta_tipo_relatorio"] = metadados.get("tipo_relatorio")
    df["meta_periodicidade"] = metadados.get("periodicidade")
    for campo in ("ano", "mes", "semana", "data"):
        valor = metadados.get(campo)
        if valor is not None:
            df[f"meta_{campo}"] = valor
    return df

def _normalizar_valores_vazios(df: pd.DataFrame) -> pd.DataFrame:
    for coluna in df.columns:
        serie = df[coluna].astype("string").str.strip()
        vazios = serie.str.lower().isin({"", "nan", "none", "null", "<na>", "n/a"})
        df[coluna] = serie.mask(vazios, pd.NA)
    return df

def _remover_colunas_artificiais(df: pd.DataFrame) -> pd.DataFrame:
    remover = []
    for coluna in df.columns:
        base = nome_coluna_base(str(coluna))
        if re.fullmatch(r"unnamed(?:_\d+)?", base, re.IGNORECASE):
            remover.append(coluna)
    if remover:
        df = df.drop(columns=remover)
    return df

def _remover_totais(df: pd.DataFrame) -> pd.DataFrame:
    if df.empty:
        return df
    mascara = pd.Series(False, index=df.index, dtype=bool)
    for coluna in list(df.columns[:3]):
        texto = df[coluna].astype("string").fillna("").map(normalizar_texto)
        mascara |= texto.str.match(MARCADORES_AGREGADOS, na=False)
    return df.loc[~mascara].copy()

def _normalizar_datas(df: pd.DataFrame) -> pd.DataFrame:
    if "data" in df.columns:
        datas = pd.to_datetime(
            df["data"].astype("string"),
            errors="coerce",
            dayfirst=True,
        )
        df = df.loc[datas.notna()].copy()
        datas = datas.loc[datas.notna()]
        df["data"] = datas.dt.strftime("%Y-%m-%d")
        return df

    if "mes_referencia" in df.columns and "dia" in df.columns:
        meses = df["mes_referencia"].astype("string").str.strip()
        dias = df["dia"].astype("string").str.strip()
        partes_mes = meses.str.extract(r"^(\d{4})-(\d{1,2})$")
        dia_valido = dias.str.fullmatch(r"\d{1,2}", na=False)
        data_texto = (
            partes_mes[0].fillna("") + "-" +
            partes_mes[1].fillna("").str.zfill(2) + "-" +
            dias.where(dia_valido, "").str.zfill(2)
        )
        datas = pd.to_datetime(data_texto, errors="coerce", format="%Y-%m-%d")
        df = df.loc[datas.notna()].copy()
        datas = datas.loc[datas.notna()]
        df["data"] = datas.dt.strftime("%Y-%m-%d")
    return df

def _normalizar_data_hora(serie: pd.Series) -> pd.Series:
    original = serie.astype("string").str.strip()
    datas = pd.to_datetime(original, errors="coerce")
    resultado = datas.dt.strftime("%Y-%m-%dT%H:%M:%S").astype("string")
    resultado = resultado.mask(original.isna() | (original == ""), pd.NA)
    return resultado

def higienizar_dataframe(df: pd.DataFrame, metadados: Dict[str, Any]) -> pd.DataFrame:
    df = df.copy()
    df.columns = desduplicar_colunas([
        normalizar_nome_coluna(coluna) for coluna in df.columns
    ])
    df = _remover_colunas_artificiais(df)

    if df.empty:
        df = _adicionar_metadados(df, metadados)
        return df

    df = _normalizar_valores_vazios(df)
    df = df.dropna(how="all").copy()
    if not df.empty:
        df = df.dropna(axis=1, how="all").copy()

    df = _remover_totais(df)
    df = _normalizar_datas(df)

    for coluna in list(df.columns):
        base = nome_coluna_base(coluna)
        if base in COLUNAS_DATA_HORA:
            df[coluna] = _normalizar_data_hora(df[coluna])
        elif base in COLUNAS_INTEIRAS:
            df[coluna] = tentar_converter_coluna_numerica(
                df[coluna], inteira=True
            )
        elif base in COLUNAS_DECIMAIS:
            df[coluna] = tentar_converter_coluna_numerica(
                df[coluna], inteira=False
            )
        else:
            df[coluna] = df[coluna].astype("string").str.strip()
            df[coluna] = df[coluna].mask(df[coluna] == "", pd.NA)

    df = _adicionar_metadados(df, metadados)
    return df