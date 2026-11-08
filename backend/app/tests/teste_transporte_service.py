import json
import logging
from datetime import datetime
import pandas as pd
import pytest
import amostras_html as A
from app.services import transporte_service as S
from app.services.transporte_columns import COLUNAS_NUMERICAS, normalizar_nome_coluna
from app.services.transporte_numbers import limpar_numero_brasileiro
from app.services.transporte_service import (
    _atualizar_intervalo_datas,
    _classificar_relatorio,
    _converter_para_registros,
    _nome_conjunto_dados,
    _SEM_COLECAO,
    processar_e_persistir_html_bytes,
    processar_html_bytes,
)
from app.services.transporte_tables import ler_tabelas_html

#_nome_conjunto_dados
@pytest.mark.parametrize("colunas, tipo, indice, esperado", [
    (["mes_referencia", "dia", "serie", "creditos_transferidos_para_cartoes", "saldo_final"], "saldos_mensal", 1, "saldos_creditos"),
    (["saldo_final"], "x", 2, "saldos_creditos"),
    (["mes_referencia", "dia", "total_vendas", "total_utilizacao", "credito_circulante"], "saldos_mensal", 2, "saldos_movimentacoes"),
    (["credito_circulante"], "x", 1, "saldos_movimentacoes"),
    (["mes_referencia", "dia", "catraca", "total_passageiros"], "passageiros_mensal", 1, "passageiros"),
    (["nao_pagantes"], "x", 3, "passageiros"),
    (["data", "linha"], "mensal_linhas", 1, "mensal_linhas"),
    (["data", "linha"], "mensal_linhas", 2, "mensal_linhas_tabela_2"),
    (["data", "linha"], "mensal__linhas_", 1, "mensal_linhas"),
    (["data"], "", 1, "transporte"),
    (["data"], "", 4, "transporte_tabela_4"),
])
def teste_nome_conjunto_dados(colunas, tipo, indice, esperado):
    assert _nome_conjunto_dados(tipo, pd.DataFrame(columns=colunas), indice) == esperado

#_converter_para_registros
def teste_converter_para_registros_dataframe_vazio():
    assert _converter_para_registros(pd.DataFrame(columns=["a"])) == []

def teste_converter_para_registros_trata_nulos_tipos_e_unicode():
    df = pd.DataFrame({
        "i": [1, 2], "f": [20434667.35, None], "t": ["ESTAÇÃO", pd.NA], "d": ["2026-08-01", None],
        "o": pd.Series([5, None], dtype="object"),
    })
    registros = _converter_para_registros(df)
    assert registros[0] == {"i": 1, "f": 20434667.35, "t": "ESTAÇÃO", "d": "2026-08-01", "o": 5}
    assert registros[1] == {"i": 2, "f": None, "t": None, "d": None, "o": None}
    assert type(registros[0]["i"]) is int
    json.dumps(registros, allow_nan=False)

#_atualizar_intervalo_datas
def _df_datas(*datas):
    return pd.DataFrame({"data": list(datas), "x": range(len(datas))})

@pytest.mark.parametrize("dataframes, inicio, fim", [
    ([_df_datas("2026-08-03", "2026-08-01", "2026-08-02")], "2026-08-01", "2026-08-03"),
    ([_df_datas("2026-08-05"), _df_datas("2026-07-30", "2026-08-01")], "2026-07-30", "2026-08-05"),
    ([_df_datas("2026-08-05"), pd.DataFrame({"x": [1]}), pd.DataFrame(columns=["data"])], "2026-08-05", "2026-08-05"),
    ([_df_datas("2026-08-01", "lixo", None)], "2026-08-01", "2026-08-01"),
    ([_df_datas("2026-12-31", "2027-01-01")], "2026-12-31", "2027-01-01"),
])
def teste_intervalo_de_datas(dataframes, inicio, fim):
    metadados = {"data_inicio": None, "data_fim": None}
    _atualizar_intervalo_datas(metadados, dataframes)
    assert (metadados["data_inicio"], metadados["data_fim"]) == (inicio, fim)

@pytest.mark.parametrize("dataframes", [[], [pd.DataFrame({"x": [1]})], [pd.DataFrame(columns=["data"])],
                                        [_df_datas("lixo", None)]])
def teste_intervalo_de_datas_sem_datas_validas_mantem_none(dataframes):
    metadados = {"data_inicio": None, "data_fim": None}
    _atualizar_intervalo_datas(metadados, dataframes)
    assert metadados == {"data_inicio": None, "data_fim": None}

#_classificar_relatorio
@pytest.mark.parametrize("tipo, categoria", [
    ("mensal", "resumo_geral"), ("mensal_fcv", "resumo_geral"), ("quinzenal", "resumo_geral"),
    ("quinzenal_fcv", "resumo_geral"), ("semanal", "resumo_geral"), ("diario", "resumo_geral"),
    ("mensal_linhas", "linhas"), ("quinzenal_linhas", "linhas"),
    ("mensal_fxhr", "fxhr"), ("quinzenal_fxhr", "fxhr"),
    ("mensal_resumo_fxhr", "resumo_fxhr"), ("quinzenal_resumo_fxhr", "resumo_fxhr"),
    ("mensal_viagens", "viagens_detalhe"), ("quinzenal_viagens", "viagens_detalhe"),
    ("mensal_viag_ninic", "ocorrencias"), ("mensal_viag_nrealiz", "ocorrencias"),
    ("quinzenal_viag_nterm", "ocorrencias"),
    ("passageiros", "passageiros"), ("passageiros_mensal", "passageiros"), ("passageiros_quinzenal", "passageiros"),
    ("saldos", "saldos"), ("saldos_mensal", "saldos"), ("saldo", "saldos"),
    #desconhecidos: nunca devem cair por engano em uma coleção existente
    ("", "desconhecido"), ("relatorio_x", "desconhecido"), ("mensal_foo", "desconhecido"),
    ("mensal_fcv_extra", "desconhecido"), ("viag", "desconhecido"), ("ninic", "desconhecido"),
])
def teste_classificar_relatorio(tipo, categoria):
    assert _classificar_relatorio(tipo) == categoria

def teste_categorias_sem_colecao_estao_declaradas():
    assert set(_SEM_COLECAO) == {"resumo_fxhr", "viagens_detalhe"}

#processar_html_bytes: retorno
@pytest.mark.parametrize("chave", sorted(A.AMOSTRAS))
def teste_estrutura_do_retorno_para_cada_tipo_de_relatorio(chave):
    amostra = A.AMOSTRAS[chave]
    resultado = processar_html_bytes(amostra.conteudo, amostra.arquivo)
    assert resultado["arquivo"] == amostra.arquivo
    assert resultado["metadados"]["tipo_relatorio"] == amostra.tipo
    assert resultado["total_registros_validos"] == amostra.registros == len(resultado["dados"])
    assert resultado["colunas"] == list(resultado["dados"][0].keys())
    json.dumps(resultado, allow_nan=False)                      # sem NaN/NaT e serializável

def teste_linhas_retorna_colunas_normalizadas_dados_e_metadados(html_linhas):
    r = processar_html_bytes(html_linhas, "Mensal_Linhas_202608.html")
    assert r["colunas"][:4] == ["data", "linha", "km_total", "viagens"]
    assert {"meta_tipo_relatorio", "meta_periodicidade", "meta_ano", "meta_mes"} <= set(r["colunas"])
    assert r["metadados"] == {"tipo_relatorio": "mensal_linhas", "periodicidade": "mensal", "ano": 2026, "mes": 8,
                              "semana": None, "data": None, "data_inicio": "2026-08-01", "data_fim": "2026-08-02"}
    primeiro = r["dados"][0]
    assert (primeiro["data"], primeiro["linha"], primeiro["km_total"], primeiro["viagens"]) == ("2026-08-01", "01", 1062.6, 132)
    assert [d["linha"] for d in r["dados"]] == ["01", "02", "01", "10"]
    assert "conjuntos_dados" not in r and "total_registros_conjuntos" not in r

def teste_linha_de_total_nao_entra_nos_registros(html_resumo):
    r = processar_html_bytes(html_resumo, "Mensal_202608.html")
    assert r["total_registros_validos"] == 3
    assert [d["data"] for d in r["dados"]] == ["2026-08-01", "2026-08-02", "2026-08-03"]
    assert sum(d["viagens_programadas"] for d in r["dados"]) == 2724       # confere com o 'Total Geral' da fonte

def teste_tipos_numericos_e_dia_da_semana(html_resumo):
    d = processar_html_bytes(html_resumo, "Mensal_202608.html")["dados"][1]
    assert d["dia_semana"] == "Dom"
    assert d["viagens_programadas"] == 800 and isinstance(d["viagens_programadas"], int)
    assert d["km_total"] == 5300.75 and isinstance(d["km_total"], float)

def teste_fcv_usa_as_chaves_por_periodo(html_fcv):
    d = processar_html_bytes(html_fcv, "Mensal_FCV_202608.html")["dados"][0]
    assert d["viagens_programadas_manha"] == 372 and d["viagens_realizadas_noite"] == 249
    assert d["viagens_programadas"] == 924 and d["viagens_realizadas"] == 924

def teste_fxhr_preserva_faixa_e_partidas_como_texto(html_fxhr):
    dados = processar_html_bytes(html_fxhr, "Mensal_FxHr_202608.html")["dados"]
    assert dados[0]["faixa_horaria"] == "4hs" and dados[0]["partidas"] == "34 > 57 > 59"
    assert dados[2]["faixa_horaria"] == "0hs"

def teste_ocorrencias_descarta_colunas_totalmente_vazias_e_converte_data_hora(html_ocorrencias):
    r = processar_html_bytes(html_ocorrencias, "Mensal_Viag_NRealiz_202608.html")
    assert "prefixo" not in r["colunas"] and "inicio_realizado" not in r["colunas"]
    assert r["dados"][0]["inicio_programado"] == "2026-08-02T19:10:00"
    assert r["dados"][0]["atendimento"] == "B. SANTA PAULA SENTIDO ESTAÇÃO"
    assert r["dados"][0]["motorista"] == "667"            # texto: o mapper converte para int

def teste_passageiros_remove_totais_de_mes_e_usa_mes_dia_como_data(html_passageiros):
    r = processar_html_bytes(html_passageiros, "Passageiros_Mensal.html")
    assert [d["data"] for d in r["dados"]] == ["2026-08-01", "2026-08-02", "2026-09-01"]
    assert r["dados"][0]["catraca"] == 5168 and r["dados"][0]["total_passageiros"] == 16544
    assert (r["metadados"]["data_inicio"], r["metadados"]["data_fim"]) == ("2026-08-01", "2026-09-01")
    assert r["metadados"]["ano"] is None          # o nome do arquivo não traz período

def teste_saldos_gera_dois_conjuntos_e_o_principal_e_o_primeiro(html_saldos):
    r = processar_html_bytes(html_saldos, "Saldos_Mensal.html")
    assert [c["nome"] for c in r["conjuntos_dados"]] == ["saldos_creditos", "saldos_movimentacoes"]
    assert r["total_registros_conjuntos"] == 4
    assert r["total_registros_validos"] == 2 and r["dados"] == r["conjuntos_dados"][0]["dados"]
    assert r["colunas"] == r["conjuntos_dados"][0]["colunas"]
    assert (r["metadados"]["data_inicio"], r["metadados"]["data_fim"]) == ("2026-08-01", "2026-08-03")

def teste_saldos_valores_negativos_milhares_e_totais_removidos(html_saldos):
    r = processar_html_bytes(html_saldos, "Saldos_Mensal.html")
    creditos, movimentos = (c["dados"] for c in r["conjuntos_dados"])
    assert creditos[0]["saldo_final"] == 20434667.35 and creditos[0]["creditos_transferidos_para_cartoes"] == 4805.0
    assert movimentos[0]["credito_circulante"] == -3380.0 and movimentos[0]["total_vendas"] == 0.0
    assert all(d["dia"] not in ("Total Mês", "Total Acumulado") for d in creditos + movimentos)
    assert len(movimentos) == 2

def teste_nomes_de_conjuntos_repetidos_recebem_sufixo():
    tabela = A.tabela(A.CAB_PASSAGEIROS, A.LINHAS_PASSAGEIROS[:1], th_em_tr=True)
    r = processar_html_bytes(A.montar_html([tabela, tabela]), "Passageiros.html")
    assert [c["nome"] for c in r["conjuntos_dados"]] == ["passageiros", "passageiros_2"]

def teste_dois_documentos_concatenados_viram_dois_conjuntos():
    r = processar_html_bytes(A.HTML_DOIS_DOCUMENTOS, "Mensal_Linhas_202608.html")
    assert [c["nome"] for c in r["conjuntos_dados"]] == ["mensal_linhas", "mensal_linhas_tabela_2"]
    assert r["total_registros_conjuntos"] == 4 + 2

#processar_html_bytes: casos limite
def teste_colunas_desordenadas_geram_os_mesmos_valores(html_colunas_desordenadas):
    desordenado = processar_html_bytes(html_colunas_desordenadas, "Mensal_Linhas_202608.html")["dados"]
    assert desordenado[0]["linha"] == "01" and desordenado[0]["viagens"] == 132 and desordenado[0]["km_total"] == 1062.6
    assert desordenado[1]["linha"] == "02" and desordenado[1]["data"] == "2026-08-01"

def teste_colunas_ausentes_nao_geram_chaves_inexistentes(html_colunas_ausentes):
    r = processar_html_bytes(html_colunas_ausentes, "Mensal_Linhas_202608.html")
    assert "km_total" not in r["colunas"] and r["dados"][0]["viagens"] == 132

def teste_somente_totais_resulta_em_zero_registros(html_apenas_totais):
    r = processar_html_bytes(html_apenas_totais, "Mensal_Linhas_202608.html")
    assert r["total_registros_validos"] == 0 and r["dados"] == []
    assert r["metadados"]["data_inicio"] is None and r["metadados"]["data_fim"] is None

def teste_tabela_somente_com_cabecalho_e_aceita():
    r = processar_html_bytes(A.HTML_SEM_REGISTROS, "Quinzenal_Viag_Ninic_202609.html")
    assert r["total_registros_validos"] == 0 and r["dados"] == [] and "data" in r["colunas"]

def teste_colunas_duplicadas_e_unnamed():
    r = processar_html_bytes(A.HTML_COLUNAS_DUPLICADAS, "Mensal_Linhas_202608.html")
    assert r["dados"][0]["linha"] == "01" and r["dados"][0]["linha_1"] == "02"
    r = processar_html_bytes(A.HTML_CABECALHO_VAZIO, "Mensal_Linhas_202608.html")
    assert not any(c.startswith("unnamed") for c in r["colunas"])

def teste_encoding_corrompido_ainda_e_lido(html_encoding_corrompido):
    r = processar_html_bytes(html_encoding_corrompido, "Mensal_Viag_NRealiz_202608.html")
    assert r["dados"][0]["atendimento"] == "B. SANTA PAULA SENTIDO ESTAÇÃO"

@pytest.mark.parametrize("conteudo, trecho", [
    (A.HTML_VAZIO, "vazio"),
    (A.HTML_SEM_TABELAS, "Nenhuma tabela operacional"),
    (A.HTML_SO_TABELA_INFO, "Nenhuma tabela operacional"),
    (A.HTML_SO_RODAPE, "Nenhuma tabela operacional"),
    (A.HTML_SEM_FECHAMENTO, "Nenhuma tabela operacional"),
])
def teste_html_sem_dados_operacionais_levanta_valueerror(conteudo, trecho):
    with pytest.raises(ValueError, match=trecho):
        processar_html_bytes(conteudo, "Mensal_Linhas_202608.html")

def teste_nenhuma_tabela_processada_levanta_valueerror(monkeypatch, html_linhas):
    monkeypatch.setattr(S, "ler_tabelas_html", lambda conteudo: [])
    with pytest.raises(ValueError, match="Nenhuma tabela pôde ser processada"):
        processar_html_bytes(html_linhas, "Mensal_Linhas_202608.html")

#persistência ponta a ponta
@pytest.mark.parametrize("chave", sorted(A.AMOSTRAS))
def teste_persistencia_de_cada_relatorio_grava_na_colecao_correta(db, chave):
    amostra = A.AMOSTRAS[chave]
    r = processar_e_persistir_html_bytes(amostra.conteudo, amostra.arquivo, db=db)
    assert r["persistencia"] == {"colecao": amostra.colecao, "documentos_afetados": amostra.afetados,
                                 "registros_descartados": None if chave == "saldos" else 0}
    assert db[amostra.colecao].count_documents({}) == amostra.afetados
    assert r["total_registros_validos"] == amostra.registros          # a resposta de processamento é mantida

@pytest.mark.parametrize("chave", sorted(A.AMOSTRAS))
def teste_reprocessar_o_mesmo_arquivo_e_idempotente(db, chave):
    amostra = A.AMOSTRAS[chave]
    processar_e_persistir_html_bytes(amostra.conteudo, amostra.arquivo, db=db)
    segunda = processar_e_persistir_html_bytes(amostra.conteudo, amostra.arquivo, db=db)
    assert segunda["persistencia"]["documentos_afetados"] == 0
    assert db[amostra.colecao].count_documents({}) == amostra.afetados

def teste_conteudo_gravado_de_linhas(db, html_linhas):
    processar_e_persistir_html_bytes(html_linhas, "Mensal_Linhas_202608.html", db=db)
    docs = list(db["viagensLinhas"].find({}, {"_id": 0}).sort([("data", 1), ("linha", 1)]))
    assert docs[0] == {"data": datetime(2026, 8, 1), "linha": "01", "kmTotal": 1062.6, "nrViagens": 132}
    assert [(d["data"].day, d["linha"]) for d in docs] == [(1, "01"), (1, "02"), (2, "01"), (2, "10")]

def teste_conteudo_gravado_de_horario_com_partidas_numericas(db, html_fxhr):
    processar_e_persistir_html_bytes(html_fxhr, "Mensal_FxHr_202608.html", db=db)
    doc = db["viagensHorario"].find_one({"linha": "01", "hora": 4}, {"_id": 0})
    assert doc == {"data": datetime(2026, 8, 1), "linha": "01", "hora": 4, "nrVeiculos": 2, "nrViagens": 3,
                   "partidas": [34, 57, 59]}
    assert db["viagensHorario"].find_one({"hora": 0}, {"_id": 0})["partidas"] == [10]
    assert sum(len(d["partidas"]) for d in db["viagensHorario"].find()) == 10

def teste_conteudo_gravado_de_passageiros_sem_totais(db, html_passageiros):
    processar_e_persistir_html_bytes(html_passageiros, "Passageiros_Mensal.html", db=db)
    doc = db["passageirosSistema"].find_one({"data": datetime(2026, 8, 1)}, {"_id": 0})
    assert doc == {"data": datetime(2026, 8, 1), "catraca": 5168, "antecipados": 676, "naoPagantes": 10700,
                   "totalPassageiros": 16544}

def teste_conteudo_gravado_de_financeiro_consolida_as_duas_tabelas_por_data(db, html_saldos):
    processar_e_persistir_html_bytes(html_saldos, "Saldos_Mensal.html", db=db)
    docs = {d["data"].day: d for d in db["financeiroSistema"].find({}, {"_id": 0})}
    assert docs[2] == {"data": datetime(2026, 8, 2), "serie": 1, "creditosTransferidosParaCartoes": 4805.0,
                       "saldoFinal": 20434667.35, "totalVendas": 4900.0, "totalUtilizacao": 1980.0,
                       "creditoCirculante": 2920.0}
    assert set(docs[1]) == {"data", "totalVendas", "totalUtilizacao", "creditoCirculante"}     # só movimentações
    assert set(docs[3]) == {"data", "serie", "creditosTransferidosParaCartoes", "saldoFinal"}   # só créditos
    assert docs[1]["creditoCirculante"] == -3380.0

def teste_resumo_e_fcv_se_complementam_no_mesmo_documento(db, html_resumo, html_fcv):
    processar_e_persistir_html_bytes(html_resumo, "Mensal_202608.html", db=db)
    r = processar_e_persistir_html_bytes(html_fcv, "Mensal_FCV_202608.html", db=db)
    assert r["persistencia"]["documentos_afetados"] == 3 and db["viagensSistema"].count_documents({}) == 3
    doc = db["viagensSistema"].find_one({"data": datetime(2026, 8, 2)}, {"_id": 0})
    assert doc["nrVeiculos"] == 30 and doc["kmTotal"] == 5300.75                       # do resumo
    assert doc["fcvPorPeriodo"]["manha"] == {"prog": 320, "real": 310, "fcv": 0.9688}  # do FCV
    assert doc["fcvTotal"] == round(790 / 800, 4)

def teste_ordem_inversa_fcv_antes_do_resumo_chega_ao_mesmo_resultado(db, html_resumo, html_fcv):
    processar_e_persistir_html_bytes(html_fcv, "Mensal_FCV_202608.html", db=db)
    processar_e_persistir_html_bytes(html_resumo, "Mensal_202608.html", db=db)
    doc = db["viagensSistema"].find_one({"data": datetime(2026, 8, 2)}, {"_id": 0})
    assert doc["nrVeiculos"] == 30 and doc["fcvPorPeriodo"]["tarde"]["real"] == 280

@pytest.mark.parametrize("arquivo", ["Quinzenal_202608.html", "Mensal_202608.html", "Semanal_2026W32.html"])
def teste_resumo_geral_de_qualquer_periodicidade_vai_para_viagens_sistema(db, html_resumo, arquivo):
    r = processar_e_persistir_html_bytes(html_resumo, arquivo, db=db)
    assert r["persistencia"]["colecao"] == "viagensSistema"

@pytest.mark.parametrize("arquivo, classificacao", [
    ("Mensal_Viag_Ninic_202608.html", "NaoIniciada"),
    ("Mensal_Viag_NRealiz_202608.html", "NaoRealizada"),
    ("Quinzenal_Viag_NTerm_202608.html", "NaoTerminada"),
])
def teste_classificacao_das_ocorrencias_vem_do_nome_do_arquivo(db, html_ocorrencias, arquivo, classificacao):
    processar_e_persistir_html_bytes(html_ocorrencias, arquivo, db=db)
    docs = list(db["viagensOcorrencias"].find({}, {"_id": 0}))
    assert len(docs) == 2 and {d["classificacao"] for d in docs} == {classificacao}

def teste_conteudo_gravado_de_ocorrencias(db):
    amostra = A.AMOSTRAS["nterm"]
    processar_e_persistir_html_bytes(amostra.conteudo, amostra.arquivo, db=db)
    doc = db["viagensOcorrencias"].find_one({}, {"_id": 0})
    assert doc["prefixo"] == 1444 and doc["motorista"] == 77 and doc["classificacao"] == "NaoTerminada"
    assert doc["inicioProgramado"] == datetime(2026, 8, 5, 10, 0) and doc["inicioRealizado"] == datetime(2026, 8, 5, 10, 2)
    assert doc["kmProd"] == 5.5 and doc["statusSaida"] == "RG"

def teste_ocorrencias_nao_realizadas_sem_prefixo_sao_gravadas(db, html_ocorrencias):
    processar_e_persistir_html_bytes(html_ocorrencias, "Mensal_Viag_NRealiz_202608.html", db=db)
    assert all(d["prefixo"] is None for d in db["viagensOcorrencias"].find())

#descartados e logging
def teste_registros_sem_chave_sao_contados_como_descartados_e_geram_warning(db, caplog):
    html = A.montar_html([A.tabela(A.CAB_LINHAS, [["01/08/2026", "01", "1,5", "3"], ["01/08/2026", "", "2,5", "4"]])])
    with caplog.at_level(logging.WARNING, logger="app.services.transporte_service"):
        r = processar_e_persistir_html_bytes(html, "Mensal_Linhas_202608.html", db=db)
    assert r["persistencia"] == {"colecao": "viagensLinhas", "documentos_afetados": 1, "registros_descartados": 1}
    assert "1 registros descartados" in caplog.text

def teste_sem_descartes_nao_emite_warning(db, html_linhas, caplog):
    with caplog.at_level(logging.WARNING, logger="app.services.transporte_service"):
        processar_e_persistir_html_bytes(html_linhas, "Mensal_Linhas_202608.html", db=db)
    assert "descartados" not in caplog.text

def teste_tabela_vazia_persiste_zero_documentos(db):
    r = processar_e_persistir_html_bytes(A.HTML_SEM_REGISTROS, "Mensal_Linhas_202608.html", db=db)
    assert r["persistencia"] == {"colecao": "viagensLinhas", "documentos_afetados": 0, "registros_descartados": 0}
    assert db.list_collection_names() == []

#saldos incompletos
def teste_saldos_com_somente_a_tabela_de_movimentacoes(db):
    html = A.montar_html([A.tabela(A.CAB_SALDOS_MOVIMENTOS, A.LINHAS_SALDOS_MOVIMENTOS, th_em_tr=True)])
    r = processar_e_persistir_html_bytes(html, "Saldos_Mensal.html", db=db)
    assert r["persistencia"]["documentos_afetados"] == 2
    assert "serie" not in db["financeiroSistema"].find_one({}, {"_id": 0})

def teste_saldos_com_tabela_nao_reconhecida_levanta_valueerror(db):
    html = A.montar_html([A.tabela(["Mês", "Dia", "Foo"], [["2026-08", "01", "1"]], th_em_tr=True)])
    with pytest.raises(ValueError, match="sem tabelas de créditos ou movimentações"):
        processar_e_persistir_html_bytes(html, "Saldos_Mensal.html", db=db)
    assert db.list_collection_names() == []

#tipos sem destino ou desconhecidos
@pytest.mark.parametrize("chave", sorted(A.AMOSTRAS_SEM_COLECAO))
def teste_relatorios_sem_colecao_sao_recusados_e_nada_e_gravado(db, chave):
    amostra = A.AMOSTRAS_SEM_COLECAO[chave]
    with pytest.raises(ValueError, match="sem coleção de destino definida"):
        processar_e_persistir_html_bytes(amostra.conteudo, amostra.arquivo, db=db)
    assert db.list_collection_names() == []

def teste_relatorios_sem_colecao_ainda_podem_ser_processados_sem_persistir():
    amostra = A.AMOSTRAS_SEM_COLECAO["viagens"]
    r = processar_html_bytes(amostra.conteudo, amostra.arquivo)
    assert r["total_registros_validos"] == 2                       # a linha de total é removida
    assert r["dados"][1]["atividade"] == "Improdutivas" and r["dados"][1].get("linha") is None

@pytest.mark.parametrize("arquivo", ["Relatorio_Desconhecido.html", "Mensal_Foo_202608.html", ".html"])
def teste_tipo_desconhecido_levanta_valueerror(db, html_linhas, arquivo):
    with pytest.raises(ValueError, match="não possui mapeamento de persistência"):
        processar_e_persistir_html_bytes(html_linhas, arquivo, db=db)
    assert db.list_collection_names() == []

def teste_html_invalido_levanta_valueerror_antes_de_tocar_no_banco(db):
    with pytest.raises(ValueError):
        processar_e_persistir_html_bytes(A.HTML_SEM_TABELAS, "Mensal_Linhas_202608.html", db=db)
    assert db.list_collection_names() == []

#resolução do banco
def teste_sem_db_informado_usa_a_connection_factory(conexao_mock, html_linhas):
    r = processar_e_persistir_html_bytes(html_linhas, "Mensal_Linhas_202608.html")
    assert r["persistencia"]["documentos_afetados"] == 4
    assert conexao_mock["viagensLinhas"].count_documents({}) == 4

def teste_sem_db_e_sem_variaveis_de_ambiente_levanta_runtimeerror(factory_limpa, sem_env_mongo, html_linhas):
    with pytest.raises(RuntimeError, match="MONGO_URI e DATABASE_NAME"):
        processar_e_persistir_html_bytes(html_linhas, "Mensal_Linhas_202608.html")

#massa real (opcional)
def _total_unico(arquivo):
    #(df bruto normalizado, linha de total) para relatórios com uma única linha de total; senão None.
    bruto = ler_tabelas_html(arquivo.read_bytes())[0]
    bruto.columns = [normalizar_nome_coluna(c) for c in bruto.columns]
    primeira = bruto.iloc[:, 0].astype("string").fillna("").str.strip().str.lower()
    totais = bruto[(primeira == "") | primeira.str.startswith("total")]
    return (bruto, totais.iloc[0]) if len(totais) == 1 else None

@pytest.mark.real_data
@pytest.mark.parametrize("arquivo", A.parametros_reais())
def teste_dados_reais_processam_sem_erro_e_sem_nan(arquivo):
    r = processar_html_bytes(arquivo.read_bytes(), arquivo.name)
    conjuntos = r.get("conjuntos_dados") or [r]
    json.dumps(r, allow_nan=False)
    assert r["total_registros_validos"] == len(r["dados"])
    for conjunto in conjuntos:
        assert conjunto["total_registros_validos"] == len(conjunto["dados"])
        if "data" in conjunto["colunas"]:
            assert all(d["data"] for d in conjunto["dados"])
    inicio, fim = r["metadados"]["data_inicio"], r["metadados"]["data_fim"]
    assert inicio is None or inicio <= fim

@pytest.mark.real_data
@pytest.mark.parametrize("arquivo", A.parametros_reais())
def teste_dados_reais_somas_e_contagens_conferem_com_o_rodape_do_html(arquivo):
    if not arquivo.name.startswith(("Mensal_", "Quinzenal_")) or "Viag_N" in arquivo.name:
        pytest.skip("relatório sem linha de total única")
    encontrado = _total_unico(arquivo)
    if encontrado is None:
        pytest.skip("sem linha de total única")
    bruto, total = encontrado
    registros = processar_html_bytes(arquivo.read_bytes(), arquivo.name)["dados"]
    assert len(registros) == len(bruto) - 1                         # nenhuma linha válida perdida
    comparadas = 0
    for coluna in COLUNAS_NUMERICAS & set(total.index):
        esperado = limpar_numero_brasileiro(total[coluna])
        if esperado is None:
            continue
        soma = sum(d[coluna] for d in registros if d.get(coluna) is not None)
        assert soma == pytest.approx(float(esperado), abs=0.06), coluna
        comparadas += 1
    assert comparadas >= 1

@pytest.mark.real_data
@pytest.mark.parametrize("arquivo", A.parametros_reais())
def teste_dados_reais_persistem_e_reprocessar_nao_duplica(db, arquivo):
    if arquivo.stat().st_size > 200_000:
        pytest.skip("o mongomock é lento para volumes grandes")
    conteudo = arquivo.read_bytes()
    tipo = processar_html_bytes(conteudo, arquivo.name)["metadados"]["tipo_relatorio"]
    if _classificar_relatorio(tipo) in _SEM_COLECAO:
        with pytest.raises(ValueError):
            processar_e_persistir_html_bytes(conteudo, arquivo.name, db=db)
        return
    primeira = processar_e_persistir_html_bytes(conteudo, arquivo.name, db=db)["persistencia"]
    total = db[primeira["colecao"]].count_documents({})
    segunda = processar_e_persistir_html_bytes(conteudo, arquivo.name, db=db)["persistencia"]
    assert segunda["documentos_afetados"] == 0
    assert db[primeira["colecao"]].count_documents({}) == total
    assert not primeira["registros_descartados"]


def teste_sobreposicao_mensal_sobre_quinzenal_ignora_iguais_e_alerta_discrepancia(db, html_resumo):
    # 1. Grava primeiro como Quinzenal
    r1 = processar_e_persistir_html_bytes(html_resumo, "Quinzenal_202608.html", db=db)
    assert "discrepancias_detectadas" not in r1
    assert r1["persistencia"]["documentos_afetados"] == 3

    # 2. Envia Mensal com exatamente os mesmos dados -> ignora (0 afetados, sem discrepâncias)
    r2 = processar_e_persistir_html_bytes(html_resumo, "Mensal_202608.html", db=db)
    assert "discrepancias_detectadas" not in r2
    assert r2["persistencia"]["documentos_afetados"] == 0

    # 3. Envia Mensal com divergência apenas no dia 02/08/2026 (km_total alterado de 5.300,75 para 5.999,00)
    html_divergente = html_resumo.replace(b"5.300,75", b"5.999,00")
    r3 = processar_e_persistir_html_bytes(html_divergente, "Mensal_202608.html", db=db)
    assert "discrepancias_detectadas" in r3
    assert len(r3["discrepancias_detectadas"]) == 1
    disc = r3["discrepancias_detectadas"][0]
    assert disc["data"] == "2026-08-02"
    assert disc["campo"] == "kmTotal"
    assert disc["valor_anterior"] == 5300.75
    assert disc["valor_novo"] == 5999.0
    assert r3["persistencia"]["documentos_afetados"] == 1
