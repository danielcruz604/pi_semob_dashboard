import math
import re
from datetime import datetime
from typing import Any, Dict, List, Optional

_PERIODOS = ("manha", "tarde", "noite")

def _vazio(valor: Any) -> bool:
    if valor is None:
        return True
    if isinstance(valor, float) and math.isnan(valor):
        return True
    return isinstance(valor, str) and not valor.strip()

def _to_str(valor: Any, default: Optional[str] = "") -> Optional[str]:
    #Texto limpo; None/NaN/vazio retornam `default` (nunca a string 'None').
    return default if _vazio(valor) else str(valor).strip()

def _to_int(valor: Any, default: Optional[int] = 0) -> Optional[int]:
    if _vazio(valor):
        return default
    try:
        numero = float(valor)
    except (ValueError, TypeError):
        return default
    return int(numero) if math.isfinite(numero) else default

def _to_float(valor: Any) -> Optional[float]:
    if _vazio(valor):
        return None
    try:
        numero = float(valor)
    except (ValueError, TypeError):
        return None
    return numero if math.isfinite(numero) else None

def _sem_none(d: Dict[str, Any]) -> Dict[str, Any]:
    return {k: v for k, v in d.items() if v is not None}

def _parse_data(valor: Any) -> Optional[datetime]:
    #Converte 'YYYY-MM-DD' (ou ISO com hora) em datetime à meia-noite.
    if _vazio(valor):
        return None
    if isinstance(valor, datetime):
        return valor.replace(hour=0, minute=0, second=0, microsecond=0)
    texto = str(valor).strip().split("T")[0].split(" ")[0]
    try:
        return datetime.strptime(texto, "%Y-%m-%d")
    except ValueError:
        return None


def _parse_data_hora(valor: Any) -> Optional[datetime]:
    #Converte string ISO 8601 em datetime.
    if _vazio(valor):
        return None
    if isinstance(valor, datetime):
        return valor
    try:
        return datetime.fromisoformat(str(valor).strip().replace("Z", "+00:00"))
    except ValueError:
        return None

def _resolver_data(item: Dict[str, Any]) -> Optional[datetime]:
    #Usa 'data'; se ausente, monta a partir de mes_referencia ('YYYY-MM' ou 'MM/YYYY') + dia. Retorna None se não for possível.
    dt = _parse_data(item.get("data"))
    if dt:
        return dt
    mes = _to_str(item.get("mes_referencia"))
    dia = _to_int(item.get("dia"), None)
    if not mes or not dia:
        return None
    m = re.fullmatch(r"(\d{4})-(\d{1,2})", mes)
    if m:
        ano, mm = int(m.group(1)), int(m.group(2))
    else:
        m = re.fullmatch(r"(\d{1,2})/(\d{4})", mes)
        if not m:
            return None
        mm, ano = int(m.group(1)), int(m.group(2))
    try:
        return datetime(ano, mm, dia)
    except ValueError:
        return None

def _calcular_fcv(real: int, prog: int) -> float:
    if not prog or prog <= 0:
        return 0.0
    return round(real / prog, 4)

def _extrair_hora(valor: Any) -> Optional[int]:
    m = re.search(r"\d{1,2}", _to_str(valor))
    return int(m.group()) if m else None


def _parse_partidas(valor: Any) -> List[Any]:
    if _vazio(valor):
        return []
    if isinstance(valor, (int, float)):
        inteiro = _to_int(valor, None)
        return [] if inteiro is None else [inteiro]
    itens = valor if isinstance(valor, (list, tuple)) else re.split(r"[;,|\s]+", str(valor).strip())
    resultado: List[Any] = []
    for item in itens:
        texto = str(item).strip()
        if not texto:
            continue
        resultado.append(int(texto) if texto.isdigit() else texto)
    return resultado

def mapear_viagens_sistema(
    dados_mensal: List[Dict[str, Any]],
    dados_fcv: Optional[List[Dict[str, Any]]] = None,
) -> List[Dict[str, Any]]:
   #Só inclui no documento os campos presentes na origem. Assim cada arquivo atualiza apenas o que conhece.
    fcv_map: Dict[datetime, Dict[str, Any]] = {}
    for item in dados_fcv or []:
        dt = _resolver_data(item)
        if dt:
            fcv_map[dt] = item

    documentos = []
    for item in dados_mensal:
        dt = _resolver_data(item)
        if not dt:
            continue

        combinado = {**item, **_sem_none(fcv_map.get(dt, {}))}
        doc: Dict[str, Any] = {"data": dt}
        
        doc.update(_sem_none({
            "diaSem": _to_str(combinado.get("dia_semana"), None),
            "nrVeiculos": _to_int(combinado.get("numero_veiculos"), None),
            "nrMaxVeicFx": _to_int(combinado.get("numero_max_veiculos_faixa"), None),
            "kmProdTotal": _to_float(combinado.get("km_produtivos")),
            "kmImprodTotal": _to_float(combinado.get("km_improdutivos")),
            "kmTotal": _to_float(combinado.get("km_total")),
        }))

        prog = _to_int(combinado.get("viagens_programadas"), None)
        real = _to_int(combinado.get("viagens_realizadas"), None)
        if prog is not None:
            doc["nrViagensProg"] = prog
        if real is not None:
            doc["nrTotalViagensRealizadas"] = real
        if prog is not None and real is not None:
            doc["fcvTotal"] = _calcular_fcv(real, prog)

        periodos: Dict[str, Any] = {}
        for p in _PERIODOS:
            pp = _to_int(combinado.get(f"viagens_programadas_{p}"), None)
            pr = _to_int(combinado.get(f"viagens_realizadas_{p}"), None)
            if pp is None and pr is None:
                continue
            pp, pr = pp or 0, pr or 0
            periodos[p] = {"prog": pp, "real": pr, "fcv": _calcular_fcv(pr, pp)}
        if periodos:
            doc["fcvPorPeriodo"] = periodos

        documentos.append(doc)
    return documentos

def mapear_viagens_linhas(dados_linhas: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    #Mensal_Linhas_*.html -> viagensLinhas.
    documentos = []
    for item in dados_linhas:
        dt = _resolver_data(item)
        linha = _to_str(item.get("linha"), None)
        if not dt or not linha:
            continue
        documentos.append({
            "data": dt,
            "linha": linha,
            "kmTotal": _to_float(item.get("km_total")),
            "nrViagens": _to_int(item.get("viagens"), None),
        })
    return documentos

def mapear_viagens_horario(dados_fx_hr: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    #Mensal_FxHr.html -> viagensHorario.
    documentos = []
    for item in dados_fx_hr:
        dt = _resolver_data(item)
        linha = _to_str(item.get("linha"), None)
        hora = _extrair_hora(item.get("faixa_horaria", item.get("hora")))
        if not dt or not linha or hora is None:
            continue
        documentos.append({
            "data": dt,
            "linha": linha,
            "hora": hora,
            "nrVeiculos": _to_int(item.get("numero_veiculos"), None),
            "nrViagens": _to_int(item.get("viagens"), None),
            "partidas": _parse_partidas(item.get("partidas")),
        })
    return documentos

def mapear_viagens_ocorrencias(
    dados_ocorrencias: List[Dict[str, Any]],
    classificacao_padrao: str = "NaoIniciada",
) -> List[Dict[str, Any]]:
    #Viag_Ninic / Viag_NRealiz / Viag_NTerm -> viagensOcorrencias.
    documentos = []
    for item in dados_ocorrencias:
        dt = _resolver_data(item)
        if not dt:
            continue
        documentos.append({
            "data": dt,
            "classificacao": _to_str(item.get("classificacao"), None) or classificacao_padrao,
            "linha": _to_str(item.get("linha")),
            "atendimento": _to_str(item.get("atendimento")),
            "prefixo": _to_int(item.get("prefixo"), None),
            "atividade": _to_str(item.get("atividade")),
            "motorista": _to_int(item.get("motorista"), None),
            "sentido": _to_str(item.get("sentido")),
            "tabela": _to_str(item.get("tabela")),
            "statusSaida": _to_str(item.get("status_saida")),
            "statusChegada": _to_str(item.get("status_chegada")),
            "inicioProgramado": _parse_data_hora(item.get("inicio_programado")),
            "inicioRealizado": _parse_data_hora(item.get("inicio_realizado")),
            "fimProgramado": _parse_data_hora(item.get("fim_programado")),
            "fimRealizado": _parse_data_hora(item.get("fim_realizado")),
            "kmProd": _to_float(item.get("km_produtivos")),
        })
    return documentos

def mapear_passageiros_sistema(dados_passageiros: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Passageiros_Mensal.html -> passegeirosSistema."""
    documentos = []
    for item in dados_passageiros:
        dt = _resolver_data(item)
        if not dt:
            continue
        documentos.append({
            "data": dt,
            "catraca": _to_int(item.get("catraca"), None),
            "antecipados": _to_int(item.get("antecipados"), None),
            "naoPagantes": _to_int(item.get("nao_pagantes"), None),
            "totalPassageiros": _to_int(item.get("total_passageiros"), None),
        })
    return documentos

def mapear_financeiro_sistema(
    dados_creditos: Optional[List[Dict[str, Any]]] = None,
    dados_movimentacoes: Optional[List[Dict[str, Any]]] = None,
) -> List[Dict[str, Any]]:
    #Consolida as duas tabelas de Saldos_Mensal.html em financeiroSistema (1 doc/data).
    por_data: Dict[datetime, Dict[str, Any]] = {}

    for item in dados_creditos or []:
        dt = _resolver_data(item)
        if dt:
            por_data.setdefault(dt, {}).update(_sem_none({
                "serie": _to_int(item.get("serie"), None),
                "creditosTransferidosParaCartoes": _to_float(item.get("creditos_transferidos_para_cartoes")),
                "saldoFinal": _to_float(item.get("saldo_final")),
            }))

    for item in dados_movimentacoes or []:
        dt = _resolver_data(item)
        if dt:
            por_data.setdefault(dt, {}).update(_sem_none({
                "totalVendas": _to_float(item.get("total_vendas")),
                "totalUtilizacao": _to_float(item.get("total_utilizacao")),
                "creditoCirculante": _to_float(item.get("credito_circulante")),
            }))

    return [{"data": dt, **valores} for dt, valores in sorted(por_data.items())]