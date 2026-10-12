import re
from decimal import Decimal, InvalidOperation
from typing import Any, Optional
import pandas as pd

def limpar_numero_brasileiro(valor: Any, inteira: bool = False) -> Optional[Decimal]:
    if valor is None:
        return None
    try:
        if pd.isna(valor):
            return None
    except (TypeError, ValueError):
        pass

    texto = str(valor).strip()
    if not texto or texto.lower() in {"nan", "none", "null", "na", "n/a", "-", "--"}:
        return None

    negativo = False
    if texto.startswith("(") and texto.endswith(")"):
        negativo = True
        texto = texto[1:-1].strip()

    texto = re.sub(r"^(?:r\$|rs\$|us\$)\s*", "", texto, flags=re.IGNORECASE)
    texto = texto.replace("\xa0", " ").replace("%", "")
    texto = re.sub(r"\s+", "", texto)

    if texto.startswith(("-", "+")):
        if texto[0] == "-":
            negativo = not negativo
        texto = texto[1:]
    if not texto:
        return None

    if "." in texto and "," in texto:
        texto = texto.replace(".", "").replace(",", ".")
    elif "," in texto:
        texto = texto.replace(",", ".")
    elif "." in texto:
        if inteira:
            if re.fullmatch(r"\d{1,3}(?:\.\d{3})+", texto):
                texto = texto.replace(".", "")
        elif re.fullmatch(r"\d{1,3}(?:\.\d{3})+", texto):
            texto = texto.replace(".", "")

    if not re.fullmatch(r"\d+(?:\.\d+)?", texto):
        return None

    try:
        numero = Decimal(texto)
    except InvalidOperation:
        return None

    if negativo:
        numero = -numero
    return numero

def tentar_converter_coluna_numerica(serie: pd.Series, inteira: bool = False) -> pd.Series:
    valores = serie.apply(lambda valor: limpar_numero_brasileiro(valor, inteira=inteira))
    if inteira:
        return pd.Series(
            [None if valor is None else int(valor) if valor == valor.to_integral_value() else float(valor) for valor in valores],
            index=serie.index,
            dtype=object,
        )
    return pd.Series(
        [None if valor is None else float(valor) for valor in valores],
        index=serie.index,
        dtype=object,
    )