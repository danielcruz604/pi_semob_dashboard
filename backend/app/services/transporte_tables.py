import io
from typing import Any, Callable, Dict, List
import pandas as pd
from app.services.transporte_columns import (
    COLUNAS_TRANSPORTE,
    PESOS_COLUNAS_TRANSPORTE,
    normalizar_nome_coluna,
)

def preservar_texto(
    valor: Any,
) -> Any:
    if valor is None:
        return None

    try:
        if pd.isna(valor):
            return None
    except (TypeError, ValueError):
        pass

    return str(valor).strip()

def _obter_converters(
    tabelas: List[pd.DataFrame],
) -> Dict[Any, Callable[[Any], Any]]:
    converters: Dict[Any, Callable[[Any], Any]] = {}

    for tabela in tabelas:
        for coluna in tabela.columns:
            converters[coluna] = preservar_texto

            if isinstance(coluna, tuple):
                for sub_coluna in coluna:
                    converters[sub_coluna] = preservar_texto

    return converters

def ler_tabelas_html(
    conteudo_bytes: bytes,
) -> List[pd.DataFrame]:
    erros: List[str] = []

    for encoding in (
        "utf-8",
        "cp1252",
        "latin-1",
    ):
        try:
            tabelas_previa = pd.read_html(
                io.BytesIO(
                    conteudo_bytes
                ),
                encoding=encoding,
                decimal=".",
                thousands=None,
                keep_default_na=True,
            )

            if not tabelas_previa:
                continue

            converters = _obter_converters(
                tabelas_previa
            )

            tabelas = pd.read_html(
                io.BytesIO(
                    conteudo_bytes
                ),
                encoding=encoding,
                decimal=".",
                thousands=None,
                converters=converters,
                keep_default_na=True,
            )

            if tabelas:
                return tabelas

        except (
            ValueError,
            UnicodeDecodeError,
            ImportError,
        ) as exc:
            erros.append(
                f"{encoding}: {exc}"
            )

    detalhe = " | ".join(erros)

    raise ValueError(
        "Não foi possível interpretar o HTML."
        + (
            f" {detalhe}"
            if detalhe
            else ""
        )
    )

def pontuar_tabela(
    df: pd.DataFrame,
) -> tuple:
    colunas_normalizadas = {
        normalizar_nome_coluna(coluna)
        for coluna in df.columns
    }

    colunas_reconhecidas = (
        colunas_normalizadas
        .intersection(
            COLUNAS_TRANSPORTE
        )
    )

    pontuacao = sum(
        PESOS_COLUNAS_TRANSPORTE.get(
            coluna,
            1,
        )
        for coluna in colunas_reconhecidas
    )

    return (
        pontuacao,
        len(colunas_reconhecidas),
        len(df),
        df.shape[0] * df.shape[1],
    )

def selecionar_tabela_principal(
    tabelas: List[pd.DataFrame],
) -> pd.DataFrame:
    tabelas_validas = [
        tabela
        for tabela in tabelas
        if tabela.shape[0] > 0
        and tabela.shape[1] > 0
    ]

    if not tabelas_validas:
        raise ValueError(
            "Nenhuma tabela com dados válidos encontrada."
        )

    return max(
        tabelas_validas,
        key=pontuar_tabela,
    )