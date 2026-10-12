import re
from typing import Any, Optional
import pandas as pd
from app.services.transporte_columns import (
    normalizar_texto,
)

def limpar_numero_brasileiro(
    valor: Any,
) -> Any:
    if valor is None:
        return None

    texto = str(valor).strip()
    texto_normalizado = normalizar_texto(texto)

    if not texto or texto_normalizado in {
        "",
        "nan",
        "none",
        "null",
        "na",
        "n_a",
        "-",
        "--",
    }:
        return None

    negativo = False

    if (
        texto.startswith("(")
        and texto.endswith(")")
    ):
        negativo = True
        texto = texto[1:-1].strip()

    texto = re.sub(
        r"^(r\$|rs\$|us\$)\s*",
        "",
        texto,
        flags=re.IGNORECASE,
    )

    percentual = "%" in texto

    texto = texto.replace(
        "%",
        "",
    )
    texto = texto.replace(
        "\xa0",
        " ",
    )
    texto = re.sub(
        r"\s+",
        "",
        texto,
    )

    if not texto or texto in {"-", "+"}:
        return None

    if "." in texto and "," in texto:
        texto = (
            texto
            .replace(".", "")
            .replace(",", ".")
        )

    elif "," in texto:
        texto = texto.replace(
            ",",
            ".",
        )

    elif "." in texto:
        partes = texto.split(".")

        if (
            len(partes) > 1
            and all(
                parte.isdigit()
                for parte in partes
            )
            and len(partes[-1]) == 3
            and 1 <= len(partes[0]) <= 3
        ):
            texto = "".join(partes)

    if not re.fullmatch(
        r"\d+(?:\.\d+)?",
        texto,
    ):
        return None

    try:
        numero = float(texto)
    except ValueError:
        return None

    if negativo:
        numero = -numero

    if percentual:
        return numero

    return numero

def tentar_converter_coluna_numerica(
    serie: pd.Series,
    inteira: bool = False,
) -> Optional[pd.Series]:
    serie_texto = (
        serie
        .astype("string")
        .str.strip()
    )

    valores_convertidos = (
        serie_texto.apply(
            limpar_numero_brasileiro
        )
    )

    validos_originais = (
        serie_texto.notna()
        & (serie_texto != "")
    )

    if validos_originais.sum() == 0:
        return None

    taxa_sucesso = (
        valores_convertidos.notna()[
            validos_originais
        ].mean()
    )

    if taxa_sucesso < 0.90:
        return None

    valores_numericos = pd.to_numeric(
        valores_convertidos,
        errors="coerce",
    )

    if inteira:
        validos = valores_numericos.dropna()

        if (
            not validos.empty
            and not (
                (validos % 1) == 0
            ).all()
        ):
            return valores_numericos.astype(
                "Float64"
            )

        return valores_numericos.astype(
            "Int64"
        )

    return valores_numericos.astype(
        "Float64"
    )