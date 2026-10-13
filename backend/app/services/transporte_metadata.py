import re
from datetime import date
from typing import Any, Dict, Optional, Tuple
from app.services.transporte_columns import normalizar_texto

def _normalizar_tipo_relatorio(nome: str) -> str:
    texto = re.sub(r"[^a-z0-9]+", "_", normalizar_texto(nome))
    return texto.strip("_")

def _inferir_periodicidade(tipo_relatorio: str) -> Optional[str]:
    partes = set(tipo_relatorio.split("_"))
    if partes.intersection({"diario", "diaria", "diariamente"}):
        return "diaria"
    if partes.intersection({"semanal", "semana"}):
        return "semanal"
    if partes.intersection({"quinzenal", "quinzena"}):
        return "quinzenal"
    if partes.intersection({"mensal", "mes"}):
        return "mensal"
    return None

def _separar_periodo(nome_base: str, periodicidade: Optional[str]) -> Tuple[str, Optional[int], Optional[int], Optional[int], Optional[str]]:
    padrao_data = re.search(r"(?:^|[_-])(\d{4})[-_]?([01]\d)[-_]?([0-3]\d)$", nome_base)
    if padrao_data:
        try:
            dt = date(int(padrao_data.group(1)), int(padrao_data.group(2)), int(padrao_data.group(3)))
        except ValueError:
            dt = None
        if dt is not None:
            return nome_base[:padrao_data.start()].rstrip("_-") , dt.year, dt.month, None, dt.isoformat()

    if periodicidade == "semanal":
        padrao_semana = re.search(r"(?:^|[_-])(\d{4})[-_]?(?:w|s(?:emana)?[-_]?)?(\d{1,2})$", nome_base, re.IGNORECASE)
        if padrao_semana:
            ano = int(padrao_semana.group(1))
            semana = int(padrao_semana.group(2))
            if 1 <= semana <= 53:
                return nome_base[:padrao_semana.start()].rstrip("_-") , ano, None, semana, None

    padrao_mes = re.search(r"(?:^|[_-])(\d{4})[-_]?([01]\d)$", nome_base)
    if padrao_mes:
        ano = int(padrao_mes.group(1))
        mes = int(padrao_mes.group(2))
        if 1 <= mes <= 12:
            return nome_base[:padrao_mes.start()].rstrip("_-") , ano, mes, None, None

    return nome_base, None, None, None, None

def extrair_metadados_nome_arquivo(nome_arquivo: str) -> Dict[str, Any]:
    nome_normalizado = re.split(r"[\\/]", nome_arquivo.strip())[-1]
    nome_base = re.sub(r"\.html?$", "", nome_normalizado, flags=re.IGNORECASE)
    tipo_preliminar = _normalizar_tipo_relatorio(nome_base)
    periodicidade = _inferir_periodicidade(tipo_preliminar)
    tipo_sem_periodo, ano, mes, semana, data = _separar_periodo(nome_base, periodicidade)
    tipo_relatorio = _normalizar_tipo_relatorio(tipo_sem_periodo) or tipo_preliminar
    periodicidade = _inferir_periodicidade(tipo_relatorio) or periodicidade

    return {
        "tipo_relatorio": tipo_relatorio,
        "periodicidade": periodicidade,
        "ano": ano,
        "mes": mes,
        "semana": semana,
        "data": data,
        "data_inicio": None,
        "data_fim": None,
    }