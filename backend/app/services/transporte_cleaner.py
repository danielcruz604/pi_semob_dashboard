import re
from typing import Any, Dict
import pandas as pd
from app.services.transporte_columns import (
    desduplicar_colunas,
    nome_coluna_base,
    normalizar_nome_coluna,
    normalizar_texto,
    coluna_eh_inteira,
    coluna_eh_numerica,
    coluna_eh_texto_estrito,
)
from app.services.transporte_numbers import (
    tentar_converter_coluna_numerica,
)

def _obter_indices_colunas_artificiais(
    df: pd.DataFrame,
) -> list[str]:
    colunas_remover = []

    for coluna in df.columns:
        base = nome_coluna_base(coluna)

        if re.fullmatch(
            r"unnamed(?:_\d+)?",
            base,
            flags=re.IGNORECASE,
        ):
            colunas_remover.append(coluna)

    return colunas_remover

def higienizar_dataframe(
    df: pd.DataFrame,
    metadados: Dict[str, Any],
) -> pd.DataFrame:
    df = df.copy()

    colunas_processadas = [
        normalizar_nome_coluna(coluna)
        for coluna in df.columns
    ]

    df.columns = desduplicar_colunas(
        colunas_processadas
    )

    colunas_artificiais = (
        _obter_indices_colunas_artificiais(
            df
        )
    )

    if colunas_artificiais:
        df = df.drop(
            columns=colunas_artificiais
        )

    df = (
        df
        .dropna(how="all")
        .dropna(
            axis=1,
            how="all",
        )
        .copy()
    )

    if df.empty:
        return df

    termos_ignorar = re.compile(
        r"^(total|subtotal|resumo|media|fonte:|emissao:|pagina:)",
        re.IGNORECASE,
    )

    mascara_ignorar = pd.Series(
        False,
        index=df.index,
        dtype=bool,
    )

    primeiras_colunas = list(
        df.columns[:3]
    )

    for col in primeiras_colunas:
        texto = (
            df[col]
            .astype("string")
            .fillna("")
            .map(normalizar_texto)
        )

        mascara_ignorar |= (
            texto.str.match(
                termos_ignorar,
                na=False,
            )
        )

    if primeiras_colunas:
        correspondencias = pd.DataFrame(
            {
                col: (
                    df[col]
                    .astype("string")
                    .fillna("")
                    .map(normalizar_texto)
                    == normalizar_texto(col)
                )
                for col in primeiras_colunas
            },
            index=df.index,
        )

        quantidade_minima = (
            2
            if len(primeiras_colunas) >= 2
            else 1
        )

        mascara_ignorar |= (
            correspondencias.sum(axis=1)
            >= quantidade_minima
        )

    df = df.loc[
        ~mascara_ignorar
    ].copy()

    for col in df.columns:
        if coluna_eh_texto_estrito(col):
            df[col] = (
                df[col]
                .astype("string")
                .str.strip()
            )
            continue

        serie = (
            df[col]
            .astype("string")
            .str.strip()
        )

        if coluna_eh_numerica(col):
            serie_num = (
                tentar_converter_coluna_numerica(
                    serie,
                    inteira=coluna_eh_inteira(
                        col
                    ),
                )
            )

            df[col] = (
                serie_num
                if serie_num is not None
                else serie
            )
        else:
            df[col] = serie

    df["meta_tipo_relatorio"] = (
        metadados[
            "tipo_relatorio"
        ]
    )

    df["meta_periodicidade"] = (
        metadados[
            "periodicidade"
        ]
    )

    if metadados["ano"] is not None:
        df["meta_ano"] = (
            metadados["ano"]
        )

    if metadados["mes"] is not None:
        df["meta_mes"] = (
            metadados["mes"]
        )

    if metadados["semana"] is not None:
        df["meta_semana"] = (
            metadados["semana"]
        )

    if metadados["data"] is not None:
        df["meta_data"] = (
            metadados["data"]
        )

    return df