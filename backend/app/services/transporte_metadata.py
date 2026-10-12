import re
from datetime import datetime
from typing import Any, Dict, Optional

from app.services.transporte_columns import normalizar_texto


def _normalizar_tipo_relatorio(nome: str) -> str:
    texto = normalizar_texto(nome).replace(" ", "_")
    texto = re.sub(r"_+", "_", texto)
    return texto.strip("_")


def _inferir_periodicidade(
    tipo_relatorio: str,
) -> Optional[str]:
    if any(
        item in tipo_relatorio
        for item in (
            "diario",
            "diaria",
            "diariamente",
        )
    ):
        return "diaria"

    if any(
        item in tipo_relatorio
        for item in (
            "semanal",
            "semana",
        )
    ):
        return "semanal"

    if any(
        item in tipo_relatorio
        for item in (
            "mensal",
            "mes",
        )
    ):
        return "mensal"

    return None


def _remover_sufixo_data(nome_base: str) -> str:
    padroes = (
        r"[_-]\d{4}[_-]?\d{2}[_-]?\d{2}$",
        r"[_-]\d{4}[_-](?:s(?:emana)?[_-]?)?\d{1,2}$",
        r"[_-]\d{4}[_-]?\d{2}$",
    )

    resultado = nome_base

    for padrao in padroes:
        resultado = re.sub(
            padrao,
            "",
            resultado,
            flags=re.IGNORECASE,
        )

    return resultado


def extrair_metadados_nome_arquivo(
    nome_arquivo: str,
) -> Dict[str, Any]:
    nome_base = re.sub(
        r"\.html?$",
        "",
        nome_arquivo.strip(),
        flags=re.IGNORECASE,
    )

    tipo_relatorio = _normalizar_tipo_relatorio(
        _remover_sufixo_data(nome_base)
    )

    periodicidade = _inferir_periodicidade(
        tipo_relatorio
    )

    metadados = {
        "tipo_relatorio": tipo_relatorio,
        "periodicidade": periodicidade,
        "ano": None,
        "mes": None,
        "semana": None,
        "data": None,
    }

    match_diario = re.search(
        r"(?:^|[_-])(\d{4})[-_]?(\d{2})[-_]?(\d{2})$",
        nome_base,
    )

    if match_diario:
        try:
            data = datetime(
                int(match_diario.group(1)),
                int(match_diario.group(2)),
                int(match_diario.group(3)),
            )
        except ValueError:
            data = None

        if data is not None:
            metadados["periodicidade"] = "diaria"
            metadados["ano"] = data.year
            metadados["mes"] = data.month
            metadados["data"] = data.date().isoformat()
            return metadados

    if periodicidade == "semanal":
        match_semanal = re.search(
            r"(?:^|[_-])(\d{4})[-_]?(?:s(?:emana)?)?[-_]?(\d{1,2})$",
            nome_base,
            flags=re.IGNORECASE,
        )

        if match_semanal:
            ano = int(match_semanal.group(1))
            semana = int(match_semanal.group(2))

            if 1 <= semana <= 53:
                metadados["ano"] = ano
                metadados["semana"] = semana
                return metadados

    match_mensal = re.search(
        r"(?:^|[_-])(\d{4})[-_]?(0[1-9]|1[0-2])$",
        nome_base,
    )

    if match_mensal:
        metadados["periodicidade"] = (
            periodicidade or "mensal"
        )
        metadados["ano"] = int(
            match_mensal.group(1)
        )
        metadados["mes"] = int(
            match_mensal.group(2)
        )

    return metadados