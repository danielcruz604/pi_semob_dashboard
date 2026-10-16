from datetime import date, datetime
import numpy as np
import pandas as pd
import pytest
from app.services import transporte_mapper as M

NAN = float("nan")

#helpers
@pytest.mark.parametrize("valor, esperado", [
    (None, True), (NAN, True), (np.nan, True), (pd.NA, True), (pd.NaT, True), ("", True), ("   ", True),
    (0, False), (0.0, False), ("0", False), ("x", False), (False, False), ([], False), ({}, False),
    ([1, 2], False), (datetime(2026, 8, 1), False),
])
def teste_vazio(valor, esperado):
    assert M._vazio(valor) is esperado

@pytest.mark.parametrize("valor, esperado", [
    (None, ""), (NAN, ""), ("", ""), (pd.NA, ""), (pd.NaT, ""), (" a ", "a"), (5, "5"), (1.5, "1.5"), ("01", "01"),
])
def teste_to_str_nunca_gera_none_nan_ou_na_como_texto(valor, esperado):
    assert M._to_str(valor) == esperado

def teste_to_str_usa_default_informado():
    assert M._to_str(None, None) is None
    assert M._to_str("", "x") == "x"

@pytest.mark.parametrize("valor, esperado", [
    ("5", 5), (" 7 ", 7), (5.9, 5), (-5.9, -5), ("1e3", 1000), (np.int64(4), 4), (0, 0), ("0", 0),
    (None, 0), ("", 0), ("abc", 0), ("5,5", 0), (NAN, 0), (float("inf"), 0), (pd.NA, 0), (pd.NaT, 0),
])
def teste_to_int_com_default_zero(valor, esperado):
    assert M._to_int(valor) == esperado

@pytest.mark.parametrize("valor", [None, "", "abc", NAN, float("inf"), float("-inf"), pd.NA])
def teste_to_int_com_default_none(valor):
    assert M._to_int(valor, None) is None

@pytest.mark.parametrize("valor, esperado", [
    ("1.5", 1.5), (2, 2.0), (np.float64(2.5), 2.5), ("-3", -3.0), (0, 0.0),
    (None, None), ("", None), ("abc", None), ("1,5", None), (NAN, None), (float("inf"), None),
    (float("-inf"), None), (pd.NA, None),
])
def teste_to_float(valor, esperado):
    assert M._to_float(valor) == esperado

def teste_sem_none_preserva_valores_falsos_mas_nao_nulos():
    assert M._sem_none({"a": None, "b": 0, "c": "", "d": False, "e": []}) == {"b": 0, "c": "", "d": False, "e": []}

@pytest.mark.parametrize("valor, esperado", [
    ("2026-08-01", datetime(2026, 8, 1)),
    ("2026-08-01T10:30:00", datetime(2026, 8, 1)),
    ("2026-08-01 10:30", datetime(2026, 8, 1)),
    (" 2026-08-01 ", datetime(2026, 8, 1)),
    (datetime(2026, 8, 1, 10, 30), datetime(2026, 8, 1)),
    (pd.Timestamp("2026-08-01 10:00"), datetime(2026, 8, 1)),
    ("01/08/2026", None), ("2026-13-01", None), ("2026-02-30", None), ("", None), (None, None),
    (NAN, None), (pd.NaT, None), (20260801, None), ("lixo", None),
])
def teste_parse_data_sempre_a_meia_noite(valor, esperado):
    assert M._parse_data(valor) == esperado

@pytest.mark.parametrize("valor, esperado", [
    ("2026-08-02T19:10:00", datetime(2026, 8, 2, 19, 10)),
    ("2026-08-02 19:10:00", datetime(2026, 8, 2, 19, 10)),
    ("2026-08-02T19:10:00Z", datetime(2026, 8, 2, 19, 10).replace(tzinfo=__import__("datetime").timezone.utc)),
    (datetime(2026, 8, 2, 1, 2), datetime(2026, 8, 2, 1, 2)),
    ("lixo", None), ("", None), (None, None), (NAN, None), (pd.NA, None), ("02/08/2026 19:10", None),
])
def teste_parse_data_hora(valor, esperado):
    assert M._parse_data_hora(valor) == esperado

@pytest.mark.parametrize("item, esperado", [
    ({"data": "2026-08-01"}, datetime(2026, 8, 1)),
    ({"mes_referencia": "2026-08", "dia": "02"}, datetime(2026, 8, 2)),
    ({"mes_referencia": "08/2026", "dia": 5}, datetime(2026, 8, 5)),
    ({"mes_referencia": "2026-8", "dia": "7"}, datetime(2026, 8, 7)),
    ({"data": "lixo", "mes_referencia": "2026-08", "dia": "3"}, datetime(2026, 8, 3)),   # fallback
    ({"data": "2026-08-01", "mes_referencia": "2026-09", "dia": "3"}, datetime(2026, 8, 1)),  # data prevalece
    ({"mes_referencia": "2026-02", "dia": "30"}, None),
    ({"mes_referencia": "2026-13", "dia": "1"}, None),
    ({"mes_referencia": "2026-08", "dia": 0}, None),
    ({"mes_referencia": "2026-08"}, None),
    ({"dia": "1"}, None),
    ({"mes_referencia": "abc", "dia": "1"}, None),
    ({"mes_referencia": None, "dia": None}, None),
    ({}, None),
])
def teste_resolver_data(item, esperado):
    assert M._resolver_data(item) == esperado

@pytest.mark.parametrize("real, prog, esperado", [
    (1, 3, 0.3333), (2, 3, 0.6667), (924, 924, 1.0), (0, 5, 0.0), (3, 2, 1.5), (5, 0, 0.0), (0, 0, 0.0), (1, -1, 0.0),
])
def teste_calcular_fcv_arredonda_em_4_casas_e_trata_divisor_zero(real, prog, esperado):
    assert M._calcular_fcv(real, prog) == esperado

@pytest.mark.parametrize("valor, esperado", [
    ("4hs", 4), ("0hs", 0), ("23hs", 23), ("4", 4), (" 9hs ", 9), ("05:00 - 05:59", 5), (7, 7), ("123", 12),
    ("hs", None), ("", None), (None, None), (NAN, None), (pd.NA, None),
])
def teste_extrair_hora(valor, esperado):
    assert M._extrair_hora(valor) == esperado

@pytest.mark.parametrize("valor, esperado", [
    ("34 > 57 > 59", [34, 57, 59]),
    ("34>57>59", [34, 57, 59]),
    ("5", [5]),
    ("7 >  8", [7, 8]),
    ("10, 20; 30", [10, 20, 30]),
    ("10 | 20", [10, 20]),
    ("1>2>", [1, 2]),
    ("a > b", []),
    ("3.5 > 4", [4]),
    ([10, "20", " 30 ", "x"], [10, 20, 30]),
    ((1, 2), [1, 2]),
    (5, [5]), (5.0, [5]),
    ("", []), ("  ", []), (None, []), (NAN, []), (pd.NA, []),
])
def teste_parse_partidas_devolve_somente_minutos_inteiros(valor, esperado):
    assert M._parse_partidas(valor) == esperado

#mapear_viagens_sistema
ITEM_RESUMO = {
    "data": "2026-08-01", "dia_semana": "Sab", "numero_veiculos": 37, "numero_max_veiculos_faixa": 35,
    "viagens_programadas": 924, "viagens_realizadas": 924, "km_produtivos": 6889.4,
    "km_improdutivos": 344.3, "km_total": 7233.7,
}
ITEM_FCV = {
    "data": "2026-08-01", "viagens_programadas_manha": 372, "viagens_realizadas_manha": 372,
    "viagens_programadas_tarde": 303, "viagens_realizadas_tarde": 300,
    "viagens_programadas_noite": 249, "viagens_realizadas_noite": 249,
    "viagens_programadas": 924, "viagens_realizadas": 921,
}

def teste_viagens_sistema_documento_completo_do_resumo():
    (doc,) = M.mapear_viagens_sistema([ITEM_RESUMO])
    assert doc == {
        "data": datetime(2026, 8, 1), "diaSem": "Sab", "nrVeiculos": 37, "nrMaxVeicFx": 35,
        "kmProdTotal": 6889.4, "kmImprodTotal": 344.3, "kmTotal": 7233.7,
        "nrViagensProg": 924, "nrTotalViagensRealizadas": 924, "fcvTotal": 1.0,
    }

def teste_viagens_sistema_fcv_por_periodo_usa_as_chaves_normalizadas_do_cleaner():
    (doc,) = M.mapear_viagens_sistema([ITEM_FCV])
    assert doc["fcvPorPeriodo"] == {
        "manha": {"prog": 372, "real": 372, "fcv": 1.0},
        "tarde": {"prog": 303, "real": 300, "fcv": 0.9901},
        "noite": {"prog": 249, "real": 249, "fcv": 1.0},
    }
    assert doc["nrViagensProg"] == 924 and doc["nrTotalViagensRealizadas"] == 921
    assert doc["fcvTotal"] == round(921 / 924, 4)

def teste_viagens_sistema_combina_resumo_e_fcv_pela_data():
    (doc,) = M.mapear_viagens_sistema([ITEM_RESUMO], [ITEM_FCV])
    assert doc["nrVeiculos"] == 37 and doc["kmTotal"] == 7233.7          # vem do resumo
    assert doc["fcvPorPeriodo"]["tarde"]["real"] == 300                  # vem do FCV
    assert doc["nrTotalViagensRealizadas"] == 921                        # FCV prevalece nos campos em comum

def teste_viagens_sistema_fcv_com_valores_nulos_nao_sobrescreve_o_resumo():
    fcv = {"data": "2026-08-01", "viagens_realizadas": None, "viagens_programadas": NAN}
    (doc,) = M.mapear_viagens_sistema([ITEM_RESUMO], [fcv])
    assert doc["nrViagensProg"] == 924 and doc["nrTotalViagensRealizadas"] == 924

def teste_viagens_sistema_fcv_de_outra_data_nao_interfere():
    fcv = {**ITEM_FCV, "data": "2026-08-02"}
    (doc,) = M.mapear_viagens_sistema([ITEM_RESUMO], [fcv])
    assert "fcvPorPeriodo" not in doc

def teste_viagens_sistema_so_inclui_campos_presentes_na_origem():
    (doc,) = M.mapear_viagens_sistema([{"data": "2026-08-01", "viagens_programadas_manha": 10,
                                        "viagens_realizadas_manha": 9}])
    assert set(doc) == {"data", "fcvPorPeriodo"}
    assert doc["fcvPorPeriodo"] == {"manha": {"prog": 10, "real": 9, "fcv": 0.9}}

@pytest.mark.parametrize("prog, real, fcv", [(0, 0, 0.0), (0, 5, 0.0), (10, 0, 0.0)])
def teste_viagens_sistema_fcv_total_com_zeros(prog, real, fcv):
    (doc,) = M.mapear_viagens_sistema([{"data": "2026-08-01", "viagens_programadas": prog, "viagens_realizadas": real}])
    assert doc["fcvTotal"] == fcv

def teste_viagens_sistema_periodo_com_so_um_lado_assume_zero_no_outro():
    (doc,) = M.mapear_viagens_sistema([{"data": "2026-08-01", "viagens_realizadas_noite": 4}])
    assert doc["fcvPorPeriodo"]["noite"] == {"prog": 0, "real": 4, "fcv": 0.0}

@pytest.mark.parametrize("item", [{}, {"data": None}, {"data": "lixo"}, {"data": "01/08/2026"}, {"dia_semana": "Sab"}])
def teste_viagens_sistema_descarta_registros_sem_data_valida(item):
    assert M.mapear_viagens_sistema([item]) == []

@pytest.mark.parametrize("entrada", [[], [{}], None])
def teste_viagens_sistema_entradas_vazias(entrada):
    assert M.mapear_viagens_sistema(entrada or []) == []

def teste_viagens_sistema_valores_nan_e_na_nao_viram_campos():
    (doc,) = M.mapear_viagens_sistema([{"data": "2026-08-01", "dia_semana": pd.NA, "km_total": NAN,
                                        "numero_veiculos": None, "km_produtivos": float("inf")}])
    assert doc == {"data": datetime(2026, 8, 1)}

def teste_viagens_sistema_processa_varias_datas_na_ordem_de_entrada():
    docs = M.mapear_viagens_sistema([{"data": "2026-08-03"}, {"data": "2026-08-01"}])
    assert [d["data"].day for d in docs] == [3, 1]

#mapear_financeiro_sistema
CREDITO = {"mes_referencia": "2026-08", "dia": "02", "serie": "1",
           "creditos_transferidos_para_cartoes": 4805.0, "saldo_final": 20434667.35}
MOVIMENTO = {"mes_referencia": "2026-08", "dia": "02", "total_vendas": 4900.0,
             "total_utilizacao": 1980.0, "credito_circulante": 2920.0}

def teste_financeiro_consolida_creditos_e_movimentacoes_em_um_documento_por_data():
    (doc,) = M.mapear_financeiro_sistema([CREDITO], [MOVIMENTO])
    assert doc == {
        "data": datetime(2026, 8, 2), "serie": 1, "creditosTransferidosParaCartoes": 4805.0,
        "saldoFinal": 20434667.35, "totalVendas": 4900.0, "totalUtilizacao": 1980.0, "creditoCirculante": 2920.0,
    }

def teste_financeiro_usa_chaves_camelcase_e_nao_snake_case():
    (doc,) = M.mapear_financeiro_sistema([CREDITO], [MOVIMENTO])
    assert not any("_" in chave for chave in doc)

def teste_financeiro_so_creditos_ou_so_movimentacoes():
    (a,) = M.mapear_financeiro_sistema([CREDITO], None)
    (b,) = M.mapear_financeiro_sistema(None, [MOVIMENTO])
    assert set(a) == {"data", "serie", "creditosTransferidosParaCartoes", "saldoFinal"}
    assert set(b) == {"data", "totalVendas", "totalUtilizacao", "creditoCirculante"}

def teste_financeiro_datas_distintas_geram_documentos_ordenados_por_data():
    movimento_dia_1 = {**MOVIMENTO, "dia": "01", "total_vendas": 0.0}
    docs = M.mapear_financeiro_sistema([CREDITO], [MOVIMENTO, movimento_dia_1])
    assert [d["data"].day for d in docs] == [1, 2]
    assert "serie" not in docs[0] and docs[1]["serie"] == 1

def teste_financeiro_aceita_data_pronta_em_vez_de_mes_e_dia():
    (doc,) = M.mapear_financeiro_sistema([{"data": "2026-08-05", "saldo_final": 1.0}])
    assert doc == {"data": datetime(2026, 8, 5), "saldoFinal": 1.0}

def teste_financeiro_valores_negativos_e_zero_sao_preservados():
    (doc,) = M.mapear_financeiro_sistema(None, [{**MOVIMENTO, "total_vendas": 0.0, "credito_circulante": -3380.0}])
    assert doc["totalVendas"] == 0.0 and doc["creditoCirculante"] == -3380.0

def teste_financeiro_nulos_nao_sobrescrevem_valores_ja_consolidados():
    docs = M.mapear_financeiro_sistema([CREDITO, {**CREDITO, "saldo_final": None}])
    assert docs[0]["saldoFinal"] == 20434667.35

def teste_financeiro_duas_series_na_mesma_data_a_ultima_prevalece():
    #comportamento atual (decisão de negócio em aberto): documento único por data
    docs = M.mapear_financeiro_sistema([{**CREDITO, "serie": "1", "saldo_final": 1.0},
                                        {**CREDITO, "serie": "2", "saldo_final": 2.0}])
    assert len(docs) == 1 and docs[0]["serie"] == 2 and docs[0]["saldoFinal"] == 2.0

@pytest.mark.parametrize("creditos, movimentos", [
    (None, None), ([], []), ([{"dia": "01"}], None), (None, [{"mes_referencia": "2026-13", "dia": "01"}]),
    ([{"mes_referencia": "2026-02", "dia": "30", "saldo_final": 1.0}], None),
])
def teste_financeiro_descarta_registros_sem_data_valida(creditos, movimentos):
    assert M.mapear_financeiro_sistema(creditos, movimentos) == []

#mapear_passageiros_sistema
def teste_passageiros_mapeia_campos_e_tipos():
    (doc,) = M.mapear_passageiros_sistema([{"data": "2026-08-01", "catraca": 5168, "antecipados": 676,
                                            "nao_pagantes": 10700, "total_passageiros": 16544}])
    assert doc == {"data": datetime(2026, 8, 1), "catraca": 5168, "antecipados": 676,
                   "naoPagantes": 10700, "totalPassageiros": 16544}

def teste_passageiros_campos_ausentes_ficam_none_e_nao_zero():
    (doc,) = M.mapear_passageiros_sistema([{"data": "2026-08-01", "catraca": 4}])
    assert doc["catraca"] == 4
    assert doc["antecipados"] is None and doc["naoPagantes"] is None and doc["totalPassageiros"] is None

def teste_passageiros_data_vem_de_mes_e_dia():
    (doc,) = M.mapear_passageiros_sistema([{"mes_referencia": "2026-08", "dia": "03", "catraca": 4}])
    assert doc["data"] == datetime(2026, 8, 3)

@pytest.mark.parametrize("item", [{}, {"catraca": 1}, {"data": "lixo"}, {"mes_referencia": "2026-08", "catraca": 1}])
def teste_passageiros_descarta_sem_data(item):
    assert M.mapear_passageiros_sistema([item]) == []

#mapear_viagens_linhas
def teste_linhas_mapeia_e_mantem_a_linha_como_texto():
    (doc,) = M.mapear_viagens_linhas([{"data": "2026-08-01", "linha": "01", "km_total": 1062.6, "viagens": 132}])
    assert doc == {"data": datetime(2026, 8, 1), "linha": "01", "kmTotal": 1062.6, "nrViagens": 132}

@pytest.mark.parametrize("linha", [None, "", "  ", NAN, pd.NA])
def teste_linhas_descarta_sem_linha_e_nunca_grava_a_string_none(linha):
    assert M.mapear_viagens_linhas([{"data": "2026-08-01", "linha": linha}]) == []

@pytest.mark.parametrize("data", [None, "", "lixo", NAN])
def teste_linhas_descarta_sem_data(data):
    assert M.mapear_viagens_linhas([{"data": data, "linha": "01"}]) == []

def teste_linhas_campos_numericos_invalidos_ficam_none():
    (doc,) = M.mapear_viagens_linhas([{"data": "2026-08-01", "linha": "01", "km_total": "x", "viagens": "y"}])
    assert doc["kmTotal"] is None and doc["nrViagens"] is None

#mapear_viagens_horario
def teste_horario_mapeia_hora_e_partidas_reais():
    (doc,) = M.mapear_viagens_horario([{"data": "2026-08-01", "linha": "01", "faixa_horaria": "4hs",
                                        "numero_veiculos": 2, "viagens": 3, "partidas": "34 > 57 > 59"}])
    assert doc == {"data": datetime(2026, 8, 1), "linha": "01", "hora": 4, "nrVeiculos": 2, "nrViagens": 3,
                   "partidas": [34, 57, 59]}

@pytest.mark.parametrize("faixa, hora", [("0hs", 0), ("23hs", 23), ("5", 5), (7, 7), ("05:00 - 05:59", 5)])
def teste_horario_converte_varios_formatos_de_faixa(faixa, hora):
    (doc,) = M.mapear_viagens_horario([{"data": "2026-08-01", "linha": "01", "faixa_horaria": faixa}])
    assert doc["hora"] == hora

def teste_horario_partidas_ausentes_viram_lista_vazia():
    (doc,) = M.mapear_viagens_horario([{"data": "2026-08-01", "linha": "01", "faixa_horaria": "4hs"}])
    assert doc["partidas"] == []

def teste_horario_aceita_chave_hora_quando_nao_ha_faixa_horaria():
    (doc,) = M.mapear_viagens_horario([{"data": "2026-08-01", "linha": "01", "hora": 7}])
    assert doc["hora"] == 7

@pytest.mark.parametrize("item", [
    {"linha": "01", "faixa_horaria": "4hs"},                           # sem data
    {"data": "2026-08-01", "faixa_horaria": "4hs"},                    # sem linha
    {"data": "2026-08-01", "linha": "01"},                             # sem hora
    {"data": "2026-08-01", "linha": "01", "faixa_horaria": "hs"},      # hora ilegível
    {"data": "2026-08-01", "linha": "", "faixa_horaria": "4hs"},
])
def teste_horario_descarta_registros_sem_chave(item):
    assert M.mapear_viagens_horario([item]) == []

#mapear_viagens_ocorrencias
ITEM_OCORRENCIA = {
    "data": "2026-08-05", "linha": "02", "atendimento": "CENTRO SENTIDO BAIRRO", "prefixo": "1444",
    "atividade": "Viagem Normal", "motorista": "77", "sentido": "I", "tabela": "3A", "status_saida": "RG",
    "status_chegada": "RG", "inicio_programado": "2026-08-05T10:00:00", "inicio_realizado": "2026-08-05T10:02:00",
    "fim_programado": "2026-08-05T10:40:00", "fim_realizado": None, "km_produtivos": 5.5,
}

def teste_ocorrencias_mapeia_tipos_e_datas():
    (doc,) = M.mapear_viagens_ocorrencias([ITEM_OCORRENCIA], classificacao_padrao="NaoTerminada")
    assert doc == {
        "data": datetime(2026, 8, 5), "classificacao": "NaoTerminada", "linha": "02",
        "atendimento": "CENTRO SENTIDO BAIRRO", "prefixo": 1444, "atividade": "Viagem Normal", "motorista": 77,
        "sentido": "I", "tabela": "3A", "statusSaida": "RG", "statusChegada": "RG",
        "inicioProgramado": datetime(2026, 8, 5, 10, 0), "inicioRealizado": datetime(2026, 8, 5, 10, 2),
        "fimProgramado": datetime(2026, 8, 5, 10, 40), "fimRealizado": None, "kmProd": 5.5,
    }

def teste_ocorrencias_classificacao_padrao_e_a_do_registro_quando_existe():
    (a,) = M.mapear_viagens_ocorrencias([ITEM_OCORRENCIA])
    (b,) = M.mapear_viagens_ocorrencias([{**ITEM_OCORRENCIA, "classificacao": "Custom"}], "NaoRealizada")
    (c,) = M.mapear_viagens_ocorrencias([{**ITEM_OCORRENCIA, "classificacao": None}], "NaoRealizada")
    assert (a["classificacao"], b["classificacao"], c["classificacao"]) == ("NaoIniciada", "Custom", "NaoRealizada")

def teste_ocorrencias_sem_prefixo_e_motorista_ficam_none_e_textos_ficam_vazios():
    item = {k: v for k, v in ITEM_OCORRENCIA.items() if k not in ("prefixo", "motorista", "status_saida", "tabela")}
    (doc,) = M.mapear_viagens_ocorrencias([item])
    assert doc["prefixo"] is None and doc["motorista"] is None
    assert doc["statusSaida"] == "" and doc["tabela"] == ""     # nunca a string 'None'

@pytest.mark.parametrize("prefixo, motorista", [("abc", "x"), ("", ""), (NAN, pd.NA)])
def teste_ocorrencias_prefixo_e_motorista_invalidos_viram_none(prefixo, motorista):
    (doc,) = M.mapear_viagens_ocorrencias([{**ITEM_OCORRENCIA, "prefixo": prefixo, "motorista": motorista}])
    assert doc["prefixo"] is None and doc["motorista"] is None

@pytest.mark.parametrize("campo", ["inicio_programado", "inicio_realizado", "fim_programado", "fim_realizado"])
def teste_ocorrencias_data_hora_invalida_vira_none_nos_campos_opcionais(campo):
    item = {**ITEM_OCORRENCIA, campo: "lixo"}
    docs = M.mapear_viagens_ocorrencias([item])
    if campo == "inicio_programado":
        assert docs == []
    else:
        assert docs[0][{"inicio_realizado": "inicioRealizado", "fim_programado": "fimProgramado",
                        "fim_realizado": "fimRealizado"}[campo]] is None

@pytest.mark.parametrize("alteracao", [
    {"data": None}, {"data": "lixo"},                                   # sem data
    {"linha": None}, {"linha": ""}, {"linha": NAN},                      # sem linha (chave)
    {"inicio_programado": None}, {"inicio_programado": ""},            # sem início programado (chave)
    {"inicio_programado": "lixo"},
])
def teste_ocorrencias_descarta_registros_sem_chave_do_upsert(alteracao):
    assert M.mapear_viagens_ocorrencias([{**ITEM_OCORRENCIA, **alteracao}]) == []

def teste_ocorrencias_sem_prefixo_nao_e_descartada_pois_e_normal_em_nao_realizadas():
    assert len(M.mapear_viagens_ocorrencias([{**ITEM_OCORRENCIA, "prefixo": None}])) == 1

def teste_ocorrencias_mantem_apenas_os_registros_validos_de_uma_lista_mista():
    docs = M.mapear_viagens_ocorrencias([ITEM_OCORRENCIA, {**ITEM_OCORRENCIA, "linha": ""}, {"data": "2026-08-01"}])
    assert len(docs) == 1

@pytest.mark.parametrize("valor", [np.array([1, 2]), np.array([np.nan, 1.0]), np.array([[1], [2]])])
def teste_vazio_com_arrays_nao_levanta_erro_e_nao_e_vazio(valor):
    assert M._vazio(valor) is False