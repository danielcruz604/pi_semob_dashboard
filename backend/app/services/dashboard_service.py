from collections import defaultdict
from datetime import datetime
from typing import Any, Dict, List, Optional
from pymongo.database import Database
from app.services.transporte_repository import (
    COL_FINANCEIRO_SISTEMA,
    COL_PASSAGEIROS_SISTEMA,
    COL_VIAGENS_HORARIO,
    COL_VIAGENS_LINHAS,
    COL_VIAGENS_OCORRENCIAS,
    COL_VIAGENS_SISTEMA,
)

AGRUPAMENTOS_VALIDOS = {"diario", "semanal", "mensal"}
CLASSIFICACOES_OCORRENCIA = ["NaoIniciada", "NaoRealizada", "NaoTerminada"]

def montar_filtro_data(
    data_inicio: Optional[str] = None, data_fim: Optional[str] = None
) -> Dict[str, Any]:
    intervalo: Dict[str, datetime] = {}
    if data_inicio:
        try:
            intervalo["$gte"] = datetime.strptime(data_inicio.strip(), "%Y-%m-%d")
        except ValueError as exc:
            raise ValueError("data_inicio inválida. Use o formato YYYY-MM-DD.") from exc
    if data_fim:
        try:
            intervalo["$lte"] = datetime.strptime(data_fim.strip(), "%Y-%m-%d")
        except ValueError as exc:
            raise ValueError("data_fim inválida. Use o formato YYYY-MM-DD.") from exc
    if "$gte" in intervalo and "$lte" in intervalo and intervalo["$gte"] > intervalo["$lte"]:
        raise ValueError("data_inicio não pode ser posterior a data_fim.")
    return {"data": intervalo} if intervalo else {}


def _chave_periodo(dt: datetime, agrupamento: str) -> str:
    if agrupamento == "mensal":
        return dt.strftime("%Y-%m")
    if agrupamento == "semanal":
        iso_ano, iso_semana, _ = dt.isocalendar()
        return f"{iso_ano}-W{iso_semana:02d}"
    return dt.strftime("%Y-%m-%d")

def _calcular_pagantes(doc: Dict[str, Any]) -> int:
    if doc.get("pagantes") is not None:
        return int(doc["pagantes"])
    return int(doc.get("catraca") or 0) + int(doc.get("antecipados") or 0)

def obter_filtros_disponiveis(db: Database) -> Dict[str, Any]:
    datas: List[datetime] = []
    for colecao in (
        COL_VIAGENS_SISTEMA,
        COL_VIAGENS_LINHAS,
        COL_PASSAGEIROS_SISTEMA,
        COL_FINANCEIRO_SISTEMA,
        COL_VIAGENS_OCORRENCIAS,
    ):
        for doc in db[colecao].find({}, {"data": 1, "_id": 0}):
            if isinstance(doc.get("data"), datetime):
                datas.append(doc["data"])

    linhas = sorted({
        str(doc["linha"]).strip()
        for colecao in (COL_VIAGENS_LINHAS, COL_VIAGENS_HORARIO, COL_VIAGENS_OCORRENCIAS)
        for doc in db[colecao].find({}, {"linha": 1, "_id": 0})
        if doc.get("linha")
    })

    return {
        "data_minima": min(datas).strftime("%Y-%m-%d") if datas else None,
        "data_maxima": max(datas).strftime("%Y-%m-%d") if datas else None,
        "linhas": linhas,
        "agrupamentos": ["diario", "semanal", "mensal"],
        "classificacoes_ocorrencia": list(CLASSIFICACOES_OCORRENCIA),
    }

def obter_resumo_dashboard(
    db: Database,
    data_inicio: Optional[str] = None,
    data_fim: Optional[str] = None,
    linha: Optional[str] = None,
) -> Dict[str, Any]:
    filtro = montar_filtro_data(data_inicio, data_fim)
    linha_limpa = linha.strip() if linha and linha.strip() else None

    docs_viagens = list(db[COL_VIAGENS_SISTEMA].find(filtro, {"_id": 0}))
    docs_pass = list(db[COL_PASSAGEIROS_SISTEMA].find(filtro, {"_id": 0}))
    docs_fin = list(db[COL_FINANCEIRO_SISTEMA].find(filtro, {"_id": 0}).sort("data", -1))

    if linha_limpa:
        filtro_linha = {**filtro, "linha": linha_limpa}
        docs_linha = list(db[COL_VIAGENS_LINHAS].find(filtro_linha, {"_id": 0}))
        km_total = sum(float(d.get("kmTotal") or 0.0) for d in docs_linha)
        km_prod = km_total
        km_improd = 0.0
        taxa_improd = 0.0
        dias_com_km = len({d["data"] for d in docs_linha if isinstance(d.get("data"), datetime)})
        media_diaria_km = round(km_total / dias_com_km, 2) if dias_com_km > 0 else 0.0
        real = sum(int(d.get("nrViagens") or 0) for d in docs_linha)
        prog = real
        fcv_medio = 1.0 if real > 0 else 0.0
        periodos_acum = {
            p: {"prog": 0, "real": 0, "fcv": 0.0} for p in ("manha", "tarde", "noite")
        }
    else:
        km_total = sum(float(d.get("kmTotal") or 0.0) for d in docs_viagens)
        km_prod = sum(float(d.get("kmProdTotal") or 0.0) for d in docs_viagens)
        km_improd = sum(float(d.get("kmImprodTotal") or 0.0) for d in docs_viagens)
        taxa_improd = round((km_improd / km_total) * 100, 2) if km_total > 0 else 0.0
        dias_com_km = sum(1 for d in docs_viagens if (d.get("kmTotal") or 0) > 0)
        media_diaria_km = round(km_total / dias_com_km, 2) if dias_com_km > 0 else 0.0

        prog = sum(int(d.get("nrViagensProg") or 0) for d in docs_viagens)
        real = sum(int(d.get("nrTotalViagensRealizadas") or 0) for d in docs_viagens)
        fcv_medio = round(real / prog, 4) if prog > 0 else 0.0

        periodos_acum = {}
        for p in ("manha", "tarde", "noite"):
            p_prog = sum(int((d.get("fcvPorPeriodo") or {}).get(p, {}).get("prog") or 0) for d in docs_viagens)
            p_real = sum(int((d.get("fcvPorPeriodo") or {}).get(p, {}).get("real") or 0) for d in docs_viagens)
            periodos_acum[p] = {
                "prog": p_prog,
                "real": p_real,
                "fcv": round(p_real / p_prog, 4) if p_prog > 0 else 0.0,
            }

    catraca = sum(int(d.get("catraca") or 0) for d in docs_pass)
    antecipados = sum(int(d.get("antecipados") or 0) for d in docs_pass)
    pagantes = sum(_calcular_pagantes(d) for d in docs_pass)
    nao_pagantes = sum(int(d.get("naoPagantes") or 0) for d in docs_pass)
    total_pass = sum(int(d.get("totalPassageiros") or 0) for d in docs_pass)
    perc_gratuidade = round((nao_pagantes / total_pass) * 100, 2) if total_pass > 0 else 0.0
    vendas = sum(float(d.get("totalVendas") or 0.0) for d in docs_fin)
    utilizacao = sum(float(d.get("totalUtilizacao") or 0.0) for d in docs_fin)
    transferidos = sum(float(d.get("creditosTransferidosParaCartoes") or 0.0) for d in docs_fin)
    circulante = sum(float(d.get("creditoCirculante") or 0.0) for d in docs_fin)
    saldo_recente = next((float(d["saldoFinal"]) for d in docs_fin if d.get("saldoFinal") is not None), None)
    receita_por_km = round(vendas / km_total, 2) if km_total > 0 else 0.0

    return {
        "periodo": {
            "data_inicio": data_inicio,
            "data_fim": data_fim,
            "agrupamento": None,
            "linha": linha_limpa,
        },
        "quilometragem": {
            "km_total": round(km_total, 2),
            "km_produtivo": round(km_prod, 2),
            "km_improdutivo": round(km_improd, 2),
            "taxa_improdutiva_percentual": taxa_improd,
            "media_diaria_km": media_diaria_km,
        },
        "viagens": {
            "programadas": prog,
            "realizadas": real,
            "diferenca": max(prog - real, 0),
            "fcv_medio": fcv_medio,
            "por_periodo": periodos_acum,
        },
        "passageiros": {
            "pagantes": pagantes,
            "catraca": catraca,
            "antecipados": antecipados,
            "nao_pagantes": nao_pagantes,
            "total_geral": total_pass,
            "percentual_gratuidade": perc_gratuidade,
        },
        "financeiro": {
            "total_vendas": round(vendas, 2),
            "total_utilizacao": round(utilizacao, 2),
            "creditos_transferidos_cartoes": round(transferidos, 2),
            "credito_circulante_acumulado": round(circulante, 2),
            "saldo_final_recente": round(saldo_recente, 2) if saldo_recente is not None else None,
            "receita_por_km": receita_por_km,
        },
    }

def obter_serie_temporal(
    db: Database,
    agrupamento: str = "diario",
    data_inicio: Optional[str] = None,
    data_fim: Optional[str] = None,
    linha: Optional[str] = None,
) -> Dict[str, Any]:
    agrupamento = (agrupamento or "diario").strip().lower()
    if agrupamento not in AGRUPAMENTOS_VALIDOS:
        raise ValueError("Agrupamento inválido. Use 'diario', 'semanal' ou 'mensal'.")

    filtro = montar_filtro_data(data_inicio, data_fim)
    linha_limpa = linha.strip() if linha and linha.strip() else None
    grupos: Dict[str, Dict[str, float]] = defaultdict(lambda: defaultdict(float))

    if linha_limpa:
        filtro_linha = {**filtro, "linha": linha_limpa}
        for d in db[COL_VIAGENS_LINHAS].find(filtro_linha, {"_id": 0}):
            if not isinstance(d.get("data"), datetime):
                continue
            chave = _chave_periodo(d["data"], agrupamento)
            km = float(d.get("kmTotal") or 0.0)
            viagens = int(d.get("nrViagens") or 0)
            grupos[chave]["km_total"] += km
            grupos[chave]["km_produtivo"] += km
            grupos[chave]["viagens_programadas"] += viagens
            grupos[chave]["viagens_realizadas"] += viagens
    else:
        for d in db[COL_VIAGENS_SISTEMA].find(filtro, {"_id": 0}):
            if not isinstance(d.get("data"), datetime):
                continue
            chave = _chave_periodo(d["data"], agrupamento)
            grupos[chave]["km_total"] += float(d.get("kmTotal") or 0.0)
            grupos[chave]["km_produtivo"] += float(d.get("kmProdTotal") or 0.0)
            grupos[chave]["km_improdutivo"] += float(d.get("kmImprodTotal") or 0.0)
            grupos[chave]["viagens_programadas"] += int(d.get("nrViagensProg") or 0)
            grupos[chave]["viagens_realizadas"] += int(d.get("nrTotalViagensRealizadas") or 0)

        for d in db[COL_PASSAGEIROS_SISTEMA].find(filtro, {"_id": 0}):
            if not isinstance(d.get("data"), datetime):
                continue
            chave = _chave_periodo(d["data"], agrupamento)
            grupos[chave]["passageiros_pagantes"] += _calcular_pagantes(d)
            grupos[chave]["passageiros_nao_pagantes"] += int(d.get("naoPagantes") or 0)
            grupos[chave]["total_passageiros"] += int(d.get("totalPassageiros") or 0)

        for d in db[COL_FINANCEIRO_SISTEMA].find(filtro, {"_id": 0}):
            if not isinstance(d.get("data"), datetime):
                continue
            chave = _chave_periodo(d["data"], agrupamento)
            grupos[chave]["total_vendas"] += float(d.get("totalVendas") or 0.0)
            grupos[chave]["total_utilizacao"] += float(d.get("totalUtilizacao") or 0.0)
            grupos[chave]["credito_circulante"] += float(d.get("creditoCirculante") or 0.0)

    serie = []
    for ref in sorted(grupos.keys()):
        g = grupos[ref]
        prog = int(g["viagens_programadas"])
        real = int(g["viagens_realizadas"])
        km_t = g["km_total"]
        vendas_t = g["total_vendas"]
        serie.append({
            "referencia": ref,
            "km_total": round(km_t, 2),
            "km_produtivo": round(g["km_produtivo"], 2),
            "km_improdutivo": round(g["km_improdutivo"], 2),
            "viagens_programadas": prog,
            "viagens_realizadas": real,
            "fcv": round(real / prog, 4) if prog > 0 else 0.0,
            "passageiros_pagantes": int(g["passageiros_pagantes"]),
            "passageiros_nao_pagantes": int(g["passageiros_nao_pagantes"]),
            "total_passageiros": int(g["total_passageiros"]),
            "total_vendas": round(vendas_t, 2),
            "total_utilizacao": round(g["total_utilizacao"], 2),
            "credito_circulante": round(g["credito_circulante"], 2),
            "receita_por_km": round(vendas_t / km_t, 2) if km_t > 0 else 0.0,
        })

    return {
        "periodo": {
            "data_inicio": data_inicio,
            "data_fim": data_fim,
            "agrupamento": agrupamento,
            "linha": linha_limpa,
        },
        "total_pontos": len(serie),
        "serie": serie,
    }

def obter_ranking_linhas(
    db: Database,
    data_inicio: Optional[str] = None,
    data_fim: Optional[str] = None,
    linha: Optional[str] = None,
) -> List[Dict[str, Any]]:
    filtro = montar_filtro_data(data_inicio, data_fim)
    if linha and linha.strip():
        filtro["linha"] = linha.strip()

    por_linha: Dict[str, Dict[str, float]] = defaultdict(lambda: {"km_total": 0.0, "viagens": 0})
    for doc in db[COL_VIAGENS_LINHAS].find(filtro, {"_id": 0}):
        cod = doc.get("linha")
        if not cod:
            continue
        por_linha[cod]["km_total"] += float(doc.get("kmTotal") or 0.0)
        por_linha[cod]["viagens"] += int(doc.get("nrViagens") or 0)

    soma_km_geral = sum(v["km_total"] for v in por_linha.values())
    ranking = []
    for cod, vals in por_linha.items():
        km_l = vals["km_total"]
        viagens_l = int(vals["viagens"])
        ranking.append({
            "linha": cod,
            "km_total": round(km_l, 2),
            "viagens": viagens_l,
            "media_km_por_viagem": round(km_l / viagens_l, 2) if viagens_l > 0 else 0.0,
            "participacao_km_percentual": round((km_l / soma_km_geral) * 100, 2) if soma_km_geral > 0 else 0.0,
        })
    return sorted(ranking, key=lambda item: (-item["km_total"], item["linha"]))

def obter_horarios_linhas(
    db: Database,
    data_inicio: Optional[str] = None,
    data_fim: Optional[str] = None,
    linha: Optional[str] = None,
) -> List[Dict[str, Any]]:
    filtro = montar_filtro_data(data_inicio, data_fim)
    if linha and linha.strip():
        filtro["linha"] = linha.strip()

    cursor = db[COL_VIAGENS_HORARIO].find(filtro, {"_id": 0}).sort([("data", 1), ("linha", 1), ("hora", 1)])
    resultado = []
    for d in cursor:
        dt = d.get("data")
        resultado.append({
            "data": dt.strftime("%Y-%m-%d") if isinstance(dt, datetime) else str(dt),
            "linha": d.get("linha", ""),
            "hora": int(d.get("hora", 0)),
            "numero_veiculos": d.get("nrVeiculos"),
            "viagens": d.get("nrViagens"),
            "partidas": list(d.get("partidas") or []),
        })
    return resultado

def obter_anomalias(
    db: Database,
    data_inicio: Optional[str] = None,
    data_fim: Optional[str] = None,
    linha: Optional[str] = None,
    classificacao: Optional[str] = None,
    tolerancia_desvio_km_pct: float = 15.0,
    limiar_fcv: float = 0.98,
    limiar_km_improd_pct: float = 10.0,
) -> Dict[str, Any]:
    filtro = montar_filtro_data(data_inicio, data_fim)
    linha_limpa = linha.strip() if linha and linha.strip() else None
    filtro_oc = dict(filtro)
    if linha_limpa:
        filtro_oc["linha"] = linha_limpa
    if classificacao and classificacao.strip():
        filtro_oc["classificacao"] = classificacao.strip()

    cursor_oc = db[COL_VIAGENS_OCORRENCIAS].find(filtro_oc, {"_id": 0}).sort("inicioProgramado", -1)
    ocorrencias = []
    por_classificacao: Dict[str, int] = defaultdict(int)
    for doc in cursor_oc:
        item = dict(doc)
        for campo_dt in ("data", "inicioProgramado", "inicioRealizado", "fimProgramado", "fimRealizado"):
            if isinstance(item.get(campo_dt), datetime):
                fmt = "%Y-%m-%d" if campo_dt == "data" else "%Y-%m-%dT%H:%M:%S"
                item[campo_dt] = item[campo_dt].strftime(fmt)
        cls = item.get("classificacao") or "NaoClassificada"
        por_classificacao[cls] += 1
        ocorrencias.append(item)

    docs_viagens = list(db[COL_VIAGENS_SISTEMA].find(filtro, {"_id": 0}).sort("data", 1))
    kms_validos = [float(d["kmTotal"]) for d in docs_viagens if (d.get("kmTotal") or 0) > 0]
    media_km = (sum(kms_validos) / len(kms_validos)) if kms_validos else 0.0

    desvios: List[Dict[str, Any]] = []
    for d in docs_viagens:
        dt_str = d["data"].strftime("%Y-%m-%d") if isinstance(d.get("data"), datetime) else str(d.get("data"))
        km_dia = float(d.get("kmTotal") or 0.0)

        #Desvio percentual em relação à quilometragem média
        if media_km > 0 and km_dia > 0:
            desvio_km_pct = abs(km_dia - media_km) / media_km * 100
            if desvio_km_pct > tolerancia_desvio_km_pct:
                desvios.append({
                    "data": dt_str,
                    "tipo": "desvio_quilometragem_media",
                    "indicador": "kmTotal",
                    "valor_observado": round(km_dia, 2),
                    "valor_referencia": round(media_km, 2),
                    "desvio_percentual": round(desvio_km_pct, 2),
                    "descricao": (
                        f"Quilometragem do dia ({km_dia:.2f} km) desviou {desvio_km_pct:.2f}% "
                        f"da média do período ({media_km:.2f} km), acima do limite de {tolerancia_desvio_km_pct:.1f}%."
                    ),
                })

        #FCV abaixo da meta
        fcv = d.get("fcvTotal")
        if fcv is not None and float(fcv) < limiar_fcv:
            fcv_val = float(fcv)
            desvios.append({
                "data": dt_str,
                "tipo": "fcv_abaixo_da_meta",
                "indicador": "fcvTotal",
                "valor_observado": round(fcv_val, 4),
                "valor_referencia": round(limiar_fcv, 4),
                "desvio_percentual": round((limiar_fcv - fcv_val) * 100, 2),
                "descricao": f"FCV diário ({fcv_val:.2%}) abaixo do limiar esperado ({limiar_fcv:.2%}).",
            })

        #Taxa de quilometragem improdutiva elevada
        km_improd = float(d.get("kmImprodTotal") or 0.0)
        if km_dia > 0:
            pct_improd = (km_improd / km_dia) * 100
            if pct_improd > limiar_km_improd_pct:
                desvios.append({
                    "data": dt_str,
                    "tipo": "km_improdutivo_elevado",
                    "indicador": "kmImprodTotal",
                    "valor_observado": round(pct_improd, 2),
                    "valor_referencia": round(limiar_km_improd_pct, 2),
                    "desvio_percentual": round(pct_improd - limiar_km_improd_pct, 2),
                    "descricao": (
                        f"Quilometragem improdutiva representou {pct_improd:.2f}% do total "
                        f"(limite: {limiar_km_improd_pct:.1f}%)."
                    ),
                })

    return {
        "periodo": {
            "data_inicio": data_inicio,
            "data_fim": data_fim,
            "agrupamento": None,
            "linha": linha_limpa,
        },
        "parametros_tolerancia": {
            "tolerancia_desvio_km_pct": tolerancia_desvio_km_pct,
            "limiar_fcv": limiar_fcv,
            "limiar_km_improd_pct": limiar_km_improd_pct,
        },
        "total_ocorrencias_viagens": len(ocorrencias),
        "ocorrencias_por_classificacao": dict(por_classificacao),
        "ocorrencias": ocorrencias,
        "total_desvios_operacionais": len(desvios),
        "desvios_operacionais": desvios,
    }