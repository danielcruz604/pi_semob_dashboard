import re
from decimal import Decimal, InvalidOperation
from typing import Any, Optional
import pandas as pd

_MILHAR_RE = re.compile(r"[1-9]\d{0,2}(?:\.\d{3})+")
_NULOS = {"nan", "none", "null", "na", "n/a", "-", "--"}

def limpar_numero_brasileiro(valor: Any, inteira: bool = False) -> Optional[Decimal]:
    #Converte textos numéricos (pt-BR ou en-US) em Decimal.
    #O parâmetro `inteira` é mantido por compatibilidade: o relatório de origem
    #usa '.' como milhar e ',' como decimal em ambos os casos.

    if valor is None:
        return None
    try:
        if pd.isna(valor):
            return None
    except (TypeError, ValueError):
        pass

    texto = str(valor).strip()
    if not texto or texto.lower() in _NULOS:
        return None

    negativo = False
    if texto.startswith("(") and texto.endswith(")"):
        negativo = True
        texto = texto[1:-1].strip()

    texto = re.sub(r"\s+", "", texto.replace("\xa0", " ").replace("%", ""))

    #Sinal e moeda podem aparecer em qualquer ordem: "-R$5,00" ou "R$-5,00".
    for _ in range(2):
        texto = re.sub(r"^(?:r\$|rs\$|us\$)", "", texto, flags=re.IGNORECASE)
        if texto[:1] in ("-", "+"):
            if texto[0] == "-":
                negativo = not negativo
            texto = texto[1:]
    if not texto:
        return None

    if "." in texto and "," in texto:
        if texto.rfind(",") > texto.rfind("."):   # 1.234,56 (pt-BR)
            texto = texto.replace(".", "").replace(",", ".")
        else:                                       # 1,234.56 (en-US)
            texto = texto.replace(",", "")
    elif "," in texto:
        texto = texto.replace(",", ".")             # múltiplas vírgulas falham no regex abaixo
    elif "." in texto and _MILHAR_RE.fullmatch(texto):
        texto = texto.replace(".", "")

    if not re.fullmatch(r"\d+(?:\.\d+)?", texto):
        return None

    try:
        numero = Decimal(texto)
    except InvalidOperation:
        return None
    return -numero if negativo else numero

def tentar_converter_coluna_numerica(serie: pd.Series, inteira: bool = False) -> pd.Series:
    valores = [limpar_numero_brasileiro(v, inteira=inteira) for v in serie]
    if inteira:
        convertidos = [
            None if v is None else int(v) if v == v.to_integral_value() else float(v)
            for v in valores
        ]
    else:
        convertidos = [None if v is None else float(v) for v in valores]
    return pd.Series(convertidos, index=serie.index, dtype=object)