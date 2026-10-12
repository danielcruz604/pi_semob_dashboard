import re
import unicodedata
from typing import Any, List, Dict
import pandas as pd

COLUNAS_TEXTO_ESTRITO = {
    "linha",
    "cod_linha",
    "codigo",
    "codigo_linha",
    "prefixo",
    "servico",
    "empresa",
    "consorcio",
    "itinerario",
    "sentido",
    "faixa_horaria",
    "veiculo",
    "codigo_veiculo",
    "id",
    "id_linha",
    "id_veiculo",
    "ramal",
}

COLUNAS_INTEIRAS = {
    "viagens",
    "passageiros",
    "passageiros_pagantes",
    "passageiros_nao_pagantes",
    "pagantes",
    "nao_pagantes",
    "quantidade",
    "qtd",
    "total_passageiros",
    "total_viagens",
}

COLUNAS_NUMERICAS = {
    "quilometragem",
    "quilometros",
    "km",
    "distancia",
    "receita",
    "receita_total",
    "arrecadacao",
    "arrecadacao_total",
    "faturamento",
    "custo",
    "custo_total",
    "despesa",
    "despesa_total",
    "tarifa",
    "valor",
    "valor_total",
    "percentual",
    "percentagem",
    "taxa",
    "media",
    "media_km",
    "total",
}

COLUNAS_TRANSPORTE = {
    "linha",
    "cod_linha",
    "codigo",
    "codigo_linha",
    "prefixo",
    "servico",
    "empresa",
    "consorcio",
    "itinerario",
    "sentido",
    "faixa_horaria",
    "horario",
    "data",
    "viagens",
    "passageiros",
    "passageiros_pagantes",
    "passageiros_nao_pagantes",
    "quilometragem",
    "quilometros",
    "km",
    "distancia",
    "receita",
    "receita_total",
    "arrecadacao",
    "arrecadacao_total",
    "faturamento",
    "custo",
    "custo_total",
    "despesa",
    "despesa_total",
    "tarifa",
    "valor",
    "valor_total",
}

PESOS_COLUNAS_TRANSPORTE = {
    "linha": 6,
    "codigo_linha": 6,
    "cod_linha": 6,
    "codigo": 5,
    "prefixo": 5,
    "data": 5,
    "viagens": 5,
    "passageiros": 5,
    "passageiros_pagantes": 5,
    "passageiros_nao_pagantes": 5,
    "quilometragem": 5,
    "empresa": 4,
    "servico": 4,
    "sentido": 3,
    "itinerario": 3,
    "receita": 3,
    "receita_total": 3,
    "arrecadacao": 3,
    "arrecadacao_total": 3,
    "faturamento": 3,
    "custo": 3,
    "custo_total": 3,
    "despesa": 3,
    "despesa_total": 3,
    "tarifa": 3,
    "valor": 2,
    "valor_total": 2,
    "horario": 2,
    "faixa_horaria": 2,
    "consorcio": 2,
    "distancia": 2,
    "quilometros": 2,
    "km": 2,
}

CABECALHOS_GENERICOS = {
    "dados",
    "dado",
    "informacao",
    "informacoes",
    "operacao",
    "transporte",
    "indicador",
    "indicadores",
    "resultado",
    "resultados",
    "campo",
    "campos",
}

ALIASES_COLUNAS = {
    "codigo da linha": "codigo_linha",
    "codigo_linha": "codigo_linha",
    "cod da linha": "cod_linha",
    "cod_linha": "cod_linha",
    "passageiros pagantes": "passageiros_pagantes",
    "passageiros nao pagantes": "passageiros_nao_pagantes",
    "passageiros naopagantes": "passageiros_nao_pagantes",
    "passageiros nao-pagantes": "passageiros_nao_pagantes",
    "quilometragem": "quilometragem",
    "quilometros": "quilometros",
    "quilometro": "quilometros",
    "km rodado": "quilometragem",
    "km rodados": "quilometragem",
    "distancia percorrida": "distancia",
    "valor arrecadado": "arrecadacao",
    "arrecadacao": "arrecadacao",
    "receita bruta": "receita",
    "receita total": "receita_total",
    "custo total": "custo_total",
    "despesa total": "despesa_total",
    "valor total": "valor_total",
}

def normalizar_texto(valor: Any) -> str:
    if valor is None:
        return ""

    try:
        if pd.isna(valor):
            return ""
    except (TypeError, ValueError):
        pass

    texto = str(valor).strip()

    texto = (
        unicodedata
        .normalize("NFKD", texto)
        .encode("ASCII", "ignore")
        .decode("utf-8")
    )

    return re.sub(r"\s+", " ", texto).lower().strip()

def _normalizar_parte_coluna(valor: Any) -> str:
    texto = normalizar_texto(valor)
    texto = re.sub(r"[^\w\s]", " ", texto)
    return re.sub(r"\s+", "_", texto).strip("_")

def normalizar_nome_coluna(coluna: Any) -> str:
    if isinstance(coluna, tuple):
        partes = []

        for item in coluna:
            parte = _normalizar_parte_coluna(item)

            if not parte or parte.startswith("unnamed"):
                continue

            tokens = [
                token
                for token in parte.split("_")
                if token not in CABECALHOS_GENERICOS
            ]

            parte = "_".join(tokens)

            if parte and parte not in partes:
                partes.append(parte)

        texto = "_".join(partes)
    else:
        texto = _normalizar_parte_coluna(coluna)

    texto = re.sub(r"_+", "_", texto).strip("_")

    if texto in ALIASES_COLUNAS:
        return ALIASES_COLUNAS[texto]

    for alias, canonico in sorted(
        ALIASES_COLUNAS.items(),
        key=lambda item: len(item[0]),
        reverse=True,
    ):
        alias_normalizado = _normalizar_parte_coluna(alias)

        if texto.endswith(f"_{alias_normalizado}"):
            prefixo = texto[
                :-(len(alias_normalizado) + 1)
            ].strip("_")

            if not prefixo or prefixo in CABECALHOS_GENERICOS:
                return canonico

    tokens = texto.split("_") if texto else []

    if len(tokens) == 2 and tokens[0] == tokens[1]:
        texto = tokens[0]

    return texto

def desduplicar_colunas(colunas: List[str]) -> List[str]:
    vistas: Dict[str, int] = {}
    novas_colunas: List[str] = []

    for col in colunas:
        col_limpa = col.strip() if col else "coluna"

        if not col_limpa:
            col_limpa = "coluna"

        if col_limpa in vistas:
            vistas[col_limpa] += 1
            novas_colunas.append(
                f"{col_limpa}_{vistas[col_limpa]}"
            )
        else:
            vistas[col_limpa] = 0
            novas_colunas.append(col_limpa)

    return novas_colunas

def nome_coluna_base(coluna: str) -> str:
    return re.sub(r"_\d+$", "", coluna)

def coluna_eh_texto_estrito(coluna: str) -> bool:
    return (
        nome_coluna_base(coluna)
        in COLUNAS_TEXTO_ESTRITO
    )

def coluna_eh_inteira(coluna: str) -> bool:
    return (
        nome_coluna_base(coluna)
        in COLUNAS_INTEIRAS
    )

def coluna_eh_numerica(coluna: str) -> bool:
    base = nome_coluna_base(coluna)

    if coluna_eh_texto_estrito(base):
        return False

    if base in COLUNAS_INTEIRAS or base in COLUNAS_NUMERICAS:
        return True

    tokens = set(base.split("_"))

    tokens_numericos = {
        "quilometragem", "quilometros", "km", "distancia", "viagens", "passageiros",
        "pagantes", "nao", "arrecadacao", "receita", "faturamento", "custo", "despesa",
        "tarifa", "valor", "percentual", "percentagem", "taxa", "quantidade", "qtd", "total"
    }

    return bool(tokens.intersection(tokens_numericos))