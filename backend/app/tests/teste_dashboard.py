import pytest
from pymongo.errors import PyMongoError
import amostras_html as A
from app.services.transporte_service import processar_e_persistir_html_bytes

def _popular_banco(db):
    for chave in ("resumo", "fcv", "linhas", "fxhr", "nrealiz", "nterm", "passageiros", "saldos"):
        amostra = A.AMOSTRAS[chave]
        processar_e_persistir_html_bytes(amostra.conteudo, amostra.arquivo, db=db)

def teste_cors_habilitado_para_integracao_com_frontend(client):
    resposta = client.options(
        "/api/dashboard/resumo-operacional",
        headers={"Origin": "http://localhost:3000", "Access-Control-Request-Method": "GET"},
    )
    assert resposta.status_code == 200
    assert "access-control-allow-origin" in resposta.headers

def teste_filtros_disponiveis_retorna_datas_e_linhas_do_banco(client, conexao_mock):
    _popular_banco(conexao_mock)
    r = client.get("/api/dashboard/filtros")
    assert r.status_code == 200
    corpo = r.json()
    assert corpo["data_minima"] == "2026-08-01"
    assert corpo["data_maxima"] == "2026-09-01"
    assert corpo["linhas"] == ["01", "02", "04", "10"]

def teste_resumo_operacional_consolida_pilares_e_receita_por_km(client, conexao_mock):
    _popular_banco(conexao_mock)
    r = client.get("/api/dashboard/resumo-operacional", params={"data_inicio": "2026-08-01", "data_fim": "2026-08-31"})
    assert r.status_code == 200
    corpo = r.json()
    assert corpo["quilometragem"]["km_total"] == pytest.approx(19884.45)
    assert corpo["viagens"]["programadas"] == 2724 and corpo["viagens"]["realizadas"] == 2714
    assert corpo["passageiros"]["pagantes"] == 9168 + 1176
    assert corpo["passageiros"]["nao_pagantes"] == 18700
    assert corpo["financeiro"]["total_vendas"] == 4900.0
    assert corpo["financeiro"]["receita_por_km"] == pytest.approx(round(4900.0 / 19884.45, 2))

def teste_resumo_operacional_filtrado_por_linha(client, conexao_mock):
    _popular_banco(conexao_mock)
    r = client.get("/api/dashboard/resumo-operacional", params={"linha": "01"})
    assert r.status_code == 200
    corpo = r.json()
    assert corpo["periodo"]["linha"] == "01"
    assert corpo["quilometragem"]["km_total"] == pytest.approx(2072.6)
    assert corpo["viagens"]["realizadas"] == 260

@pytest.mark.parametrize("agrupamento, pontos_minimos", [
    ("diario", 3),
    ("semanal", 2),
    ("mensal", 2),
])
def teste_serie_temporal_agrupa_por_dia_semana_e_mes(client, conexao_mock, agrupamento, pontos_minimos):
    _popular_banco(conexao_mock)
    r = client.get("/api/dashboard/serie-temporal", params={"agrupamento": agrupamento})
    assert r.status_code == 200
    assert r.json()["total_pontos"] >= pontos_minimos

def teste_serie_temporal_filtrada_por_linha(client, conexao_mock):
    _popular_banco(conexao_mock)
    r = client.get("/api/dashboard/serie-temporal", params={"agrupamento": "diario", "linha": "01"})
    assert r.status_code == 200
    serie = r.json()["serie"]
    assert len(serie) == 2
    assert serie[0]["km_total"] == pytest.approx(1062.6) and serie[0]["viagens_realizadas"] == 132

def teste_ranking_linhas_calcula_media_e_participacao(client, conexao_mock):
    _popular_banco(conexao_mock)
    r = client.get("/api/dashboard/linhas-ranking")
    assert r.status_code == 200
    linhas = r.json()
    assert [item["linha"] for item in linhas] == ["01", "02", "10"]
    assert linhas[0]["km_total"] == pytest.approx(2072.6)
    assert linhas[0]["media_km_por_viagem"] == pytest.approx(round(2072.6 / 260, 2))
    assert sum(item["participacao_km_percentual"] for item in linhas) == pytest.approx(100.0, abs=0.1)

def teste_horarios_retorna_partidas_da_linha(client, conexao_mock):
    _popular_banco(conexao_mock)
    r = client.get("/api/dashboard/horarios", params={"linha": "01"})
    assert r.status_code == 200
    dados = r.json()
    assert len(dados) == 3 and dados[0]["partidas"] == [34, 57, 59]

def teste_anomalias_detecta_desvio_de_km_fcv_e_ocorrencias(client, conexao_mock):
    _popular_banco(conexao_mock)
    #No resumo de amostra: dia 01 = 7233.7 km, dia 02 = 5300.75 km, dia 03 = 7350.0 km (média = 6628.15 km)
    #Desvio do dia 02 é ~20.03% (> 15% padrão)
    r = client.get("/api/dashboard/anomalias", params={"tolerancia_desvio_km_pct": 15.0, "limiar_fcv": 0.99})
    assert r.status_code == 200
    corpo = r.json()
    assert corpo["total_ocorrencias_viagens"] == 3
    assert corpo["ocorrencias_por_classificacao"] == {"NaoRealizada": 2, "NaoTerminada": 1}
    tipos_desvio = {d["tipo"] for d in corpo["desvios_operacionais"]}
    assert "desvio_quilometragem_media" in tipos_desvio
    assert "fcv_abaixo_da_meta" in tipos_desvio

@pytest.mark.parametrize("params", [
    {"data_inicio": "data-invalida"},
    {"data_fim": "2026/08/01"},
    {"data_inicio": "2026-08-10", "data_fim": "2026-08-01"},
])
def teste_filtros_de_data_invalidos_retornam_400(client, conexao_mock, params):
    assert client.get("/api/dashboard/resumo-operacional", params=params).status_code == 400


def teste_falha_de_banco_no_dashboard_retorna_503_sem_vazar_segredo(client, monkeypatch):
    def falhar(*args, **kwargs):
        raise PyMongoError("mongodb://admin:segredo@host:27017")
    monkeypatch.setattr("app.routes.dashboard_route.obter_resumo_dashboard", falhar)
    r = client.get("/api/dashboard/resumo-operacional")
    assert r.status_code == 503
    assert "segredo" not in r.text