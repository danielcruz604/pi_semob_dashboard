import pandas as pd
import pytest
from app.services.transporte_cleaner import (
    COLUNAS_DATA_HORA,
    _converter_datas,
    _normalizar_data_hora,
    _normalizar_datas,
    _remover_colunas_artificiais,
    _remover_totais,
    higienizar_dataframe,
)

META = {"tipo_relatorio": "mensal_linhas", "periodicidade": "mensal", "ano": 2026, "mes": 8, "semana": None, "data": None}

def _df(**colunas):
    return pd.DataFrame({k: v for k, v in colunas.items()})

def _linhas(tipo_total, posicao):
    #DataFrame de 3 colunas com uma linha de total na coluna `posicao` e uma linha válida.
    total = ["01/08/2026", "01", "5"]
    total[posicao] = tipo_total
    return pd.DataFrame([["02/08/2026", "02", "7"], total], columns=["a", "b", "c"])

#remoção de linhas agregadas
@pytest.mark.parametrize("posicao", [0, 1, 2])
@pytest.mark.parametrize("rotulo", [
    "Total", "TOTAL GERAL", "Total Mês", "total_mes", "Total Acumulado", "Subtotal", "Subtotal linha",
    "Resumo", "Resumo do mês", "Fonte: SmartDataSource", "Emissão: 04/09/2026", "Página: 1",
])
def teste_remove_linhas_agregadas_nas_tres_primeiras_colunas(rotulo, posicao):
    resultado = _remover_totais(_linhas(rotulo, posicao))
    assert resultado["a"].tolist() == ["02/08/2026"]

@pytest.mark.parametrize("rotulo", [
    "Totalizador", "Totais", "Subtotais", "Resumos", "Resumido", "Centro Total", "Linha Total", "Atotal", "01",
])
def teste_preserva_registros_com_texto_parecido_com_total(rotulo):
    resultado = _remover_totais(_linhas(rotulo, 1))
    assert len(resultado) == 2

def teste_total_so_e_procurado_nas_tres_primeiras_colunas():
    df = pd.DataFrame([["01/08/2026", "01", "5", "Total Geral"]], columns=list("abcd"))
    assert len(_remover_totais(df)) == 1

def teste_remover_totais_em_dataframe_vazio_devolve_vazio():
    assert _remover_totais(pd.DataFrame(columns=["a", "b", "c"])).empty

def teste_remover_totais_nao_altera_a_entrada():
    df = _linhas("Total", 0)
    copia = df.copy()
    _remover_totais(df)
    assert df.equals(copia)

def teste_linhas_de_total_com_primeira_celula_vazia_saem_pelo_filtro_de_data():
    df = _df(Data=["01/08/2026", "", None], Linha=["01", "", ""], kmTotal=["1,5", "10,0", "20,0"])
    resultado = higienizar_dataframe(df, META)
    assert resultado["data"].tolist() == ["2026-08-01"]
    assert resultado["km_total"].tolist() == [1.5]

def teste_tabela_somente_com_totais_resulta_em_zero_registros_sem_excecao():
    df = _df(Data=["Total Geral", ""], Linha=["", ""], kmTotal=["1,5", "9,0"])
    resultado = higienizar_dataframe(df, META)
    assert len(resultado) == 0
    assert "data" in resultado.columns

def teste_somente_totais_no_formato_mes_dia():
    df = _df(**{"Mês": ["2026-08"], "Dia": ["Total Mês"], "Catraca": ["1.000"]})
    resultado = higienizar_dataframe(df, META)
    assert len(resultado) == 0
    assert {"mes_referencia", "dia", "catraca", "data"} <= set(resultado.columns)

#conversão de datas (coluna 'data')
@pytest.mark.parametrize("entrada, esperado", [
    (["01/08/2026", "13/08/2026"], ["2026-08-01", "2026-08-13"]),          # dd/mm/aaaa
    (["1/8/2026", "13/8/2026"], ["2026-08-01", "2026-08-13"]),             # sem zero à esquerda
    (["01-08-2026", "13-08-2026"], ["2026-08-01", "2026-08-13"]),
    (["01.08.2026", "13.08.2026"], ["2026-08-01", "2026-08-13"]),
    (["01/08/26"], ["2026-08-01"]),                                        # ano com 2 dígitos
    (["2026-08-01", "2026-08-13"], ["2026-08-01", "2026-08-13"]),          # ISO: NÃO pode trocar dia e mês
    (["2026-01-08"], ["2026-01-08"]),
    (["2026/08/13"], ["2026-08-13"]),
    (["2026-08-01 10:30:00"], ["2026-08-01"]),
    (["2026-08-01T10:30:00"], ["2026-08-01"]),
    (["13/08/2026", "2026-08-13"], ["2026-08-13", "2026-08-13"]),          # formatos misturados
    ([" 01/08/2026 "], ["2026-08-01"]),
])
def teste_normaliza_datas_para_iso(entrada, esperado):
    df = _df(data=entrada, valor=["1"] * len(entrada))
    assert _normalizar_datas(df)["data"].tolist() == esperado

@pytest.mark.parametrize("invalido", ["", None, "32/13/2026", "lixo", "00/00/0000", "31/02/2026", "2026-13-01",
                                      "2026-08", "08/2026", "19:10", "Total Geral"])
def teste_datas_invalidas_removem_a_linha(invalido):
    df = _df(data=["01/08/2026", invalido], valor=["1", "2"])
    resultado = _normalizar_datas(df)
    assert resultado["data"].tolist() == ["2026-08-01"]
    assert resultado["valor"].tolist() == ["1"]

def teste_iso_nao_troca_dia_e_mes_em_nenhuma_versao_do_pandas():
    #regressão: com dayfirst=True, '2026-08-01' era lido como 2026-01-08
    datas = _converter_datas(pd.Series(["2026-08-01", "2026-08-13", "2026-12-31"]))
    assert datas.dt.strftime("%Y-%m-%d").tolist() == ["2026-08-01", "2026-08-13", "2026-12-31"]

def teste_converter_datas_preserva_o_indice_original():
    serie = pd.Series(["01/08/2026", "lixo", "2026-08-03"], index=[7, 7, 9])
    resultado = _converter_datas(serie)
    assert list(resultado.index) == [7, 7, 9]
    assert resultado.notna().tolist() == [True, False, True]

@pytest.mark.parametrize("entrada", [[], [None, None], ["lixo", ""]])
def teste_converter_datas_sem_nenhuma_data_valida(entrada):
    resultado = _converter_datas(pd.Series(entrada, dtype="object"))
    assert len(resultado) == len(entrada)
    assert resultado.isna().all()

def teste_dataframe_sem_coluna_de_data_nem_mes_dia_fica_inalterado():
    df = _df(x=["a", "b"], y=["1", "2"])
    assert _normalizar_datas(df).equals(df)

#data a partir de mês + dia
@pytest.mark.parametrize("mes, dia, esperado", [
    ("2026-08", "02", "2026-08-02"),
    ("2026-8", "5", "2026-08-05"),
    ("2026-08", "31", "2026-08-31"),
    ("2026-02", "28", "2026-02-28"),
    (" 2026-08 ", " 09 ", "2026-08-09"),
])
def teste_data_construida_a_partir_de_mes_referencia_e_dia(mes, dia, esperado):
    df = _df(mes_referencia=[mes], dia=[dia], catraca=["1"])
    assert _normalizar_datas(df)["data"].tolist() == [esperado]

@pytest.mark.parametrize("mes, dia", [
    ("2026-02", "30"), ("2026-13", "01"), ("2026-08", "x"), ("2026-08", "Total Mês"), ("2026-08", ""),
    ("2026-08", "100"), ("08/2026", "01"), ("", "01"), (None, "01"), ("2026-08", None), ("2026-00", "01"),
])
def teste_mes_e_dia_invalidos_removem_a_linha(mes, dia):
    df = _df(mes_referencia=["2026-08", mes], dia=["01", dia], catraca=["1", "2"])
    assert _normalizar_datas(df)["data"].tolist() == ["2026-08-01"]

def teste_somente_mes_sem_coluna_dia_nao_cria_coluna_data():
    df = _df(mes_referencia=["2026-08"], catraca=["1"], antecipados=["2"])
    resultado = higienizar_dataframe(df, META)
    assert "data" not in resultado.columns and len(resultado) == 1

#data e hora
@pytest.mark.parametrize("entrada, esperado", [
    (["2026-08-02 19:10:00", "2026-08-03 08:05:00"], ["2026-08-02T19:10:00", "2026-08-03T08:05:00"]),
    (["2026-08-02T19:10:00", "2026-08-03T08:05:00"], ["2026-08-02T19:10:00", "2026-08-03T08:05:00"]),
    (["2026-08-02 19:10", "2026-08-03 08:05"], ["2026-08-02T19:10:00", "2026-08-03T08:05:00"]),
    (["2026-08-02 19:10:00", "2026-08-03T08:05:00"], ["2026-08-02T19:10:00", "2026-08-03T08:05:00"]),
    (["02/08/2026 19:10", "15/08/2026 10:00"], ["2026-08-02T19:10:00", "2026-08-15T10:00:00"]),   # dia primeiro
    (["02/08/2026 19:10:30"], ["2026-08-02T19:10:30"]),
    (["2026-08-02"], ["2026-08-02T00:00:00"]),
])
def teste_normaliza_data_hora_para_iso_com_t(entrada, esperado):
    assert _normalizar_data_hora(pd.Series(entrada, dtype="string")).tolist() == esperado

@pytest.mark.parametrize("entrada", ["", "   ", None, "lixo", "19:10", "2026-13-45 10:00:00"])
def teste_data_hora_invalida_ou_vazia_vira_nulo(entrada):
    resultado = _normalizar_data_hora(pd.Series(["2026-08-02 19:10:00", entrada], dtype="string"))
    assert resultado.iloc[0] == "2026-08-02T19:10:00"
    assert pd.isna(resultado.iloc[1])

def teste_colunas_de_data_hora_do_cleaner_batem_com_o_que_o_mapper_le():
    assert COLUNAS_DATA_HORA == {"inicio_programado", "inicio_realizado", "fim_programado", "fim_realizado"}

def teste_higienizar_converte_colunas_de_data_hora():
    df = _df(Data=["02/08/2026"], Linha=["04"], inicioProgramado=["2026-08-02 19:10:00"], inicioRealizado=[""])
    resultado = higienizar_dataframe(df, META)
    assert resultado["inicio_programado"].tolist() == ["2026-08-02T19:10:00"]
    assert "inicio_realizado" not in resultado.columns  # coluna 100% vazia é descartada

#colunas artificiais (unnamed)
@pytest.mark.parametrize("colunas", [
    ["unnamed", "data"], ["unnamed_0", "data"], ["unnamed_0", "unnamed_0_1", "data"], ["data", "unnamed_12"],
])
def teste_remove_colunas_unnamed(colunas):
    df = pd.DataFrame([["x"] * len(colunas)], columns=colunas)
    assert [c for c in _remover_colunas_artificiais(df).columns] == ["data"]

@pytest.mark.parametrize("colunas", [["unnamed_a", "data"], ["nao_unnamed", "data"], ["data", "linha"]])
def teste_nao_remove_colunas_que_apenas_lembram_unnamed(colunas):
    df = pd.DataFrame([["x"] * len(colunas)], columns=colunas)
    assert list(_remover_colunas_artificiais(df).columns) == colunas

def teste_higienizar_remove_unnamed_do_pandas():
    df = pd.DataFrame([["a", "01/08/2026", "1"]], columns=["Unnamed: 0", "Data", "Unnamed: 2"])
    resultado = higienizar_dataframe(df, META)
    assert "unnamed_0" not in resultado.columns and "unnamed_2" not in resultado.columns
    assert resultado["data"].tolist() == ["2026-08-01"]

def teste_higienizar_com_cabecalho_multiindex():
    colunas = pd.MultiIndex.from_tuples([("Unnamed: 0_level_0", "Data"), ("dados", "Linha"), ("km", "km")])
    df = pd.DataFrame([["01/08/2026", "01", "5"]], columns=colunas)
    resultado = higienizar_dataframe(df, META)
    assert [c for c in resultado.columns if not c.startswith("meta_")] == ["data", "linha", "km"]

#células vazias e texto
@pytest.mark.parametrize("vazio", ["", "   ", "nan", "NaN", "None", "none", "null", "NULL", "<NA>", "N/A", "n/a", None])
def teste_celulas_vazias_viram_nulo_em_colunas_de_texto(vazio):
    df = _df(Data=["01/08/2026", "02/08/2026"], Linha=["01", vazio], Obs=["ok", "ok"])
    resultado = higienizar_dataframe(df, META)
    assert resultado["linha"].tolist()[0] == "01"
    assert pd.isna(resultado["linha"].tolist()[1])

def teste_colunas_totalmente_vazias_sao_descartadas_e_linhas_totalmente_vazias_tambem():
    df = _df(Data=["01/08/2026", None, "02/08/2026"], Linha=["01", None, "02"], Obs=["", "nan", "null"],
             kmTotal=["1", None, "2"])
    resultado = higienizar_dataframe(df, META)
    assert "obs" not in resultado.columns
    assert len(resultado) == 2

def teste_texto_e_aparado_e_nao_e_convertido_em_numero():
    df = _df(Data=["01/08/2026", "02/08/2026"], Linha=["  01  ", "007"], kmTotal=["1", "2"])
    assert higienizar_dataframe(df, META)["linha"].tolist() == ["01", "007"]

def teste_colunas_duplicadas_recebem_sufixo():
    df = pd.DataFrame([["01/08/2026", "1", "2"]], columns=["Data", "Linha", "Linha"])
    resultado = higienizar_dataframe(df, META)
    assert resultado["linha"].tolist() == ["1"] and resultado["linha_1"].tolist() == ["2"]

#conversão numérica no cleaner
def teste_colunas_inteiras_e_decimais_sao_convertidas():
    df = _df(Data=["01/08/2026"] * 3, Linha=["01"] * 3, nrViagens=["1.234", "5,5", "abc"],
             kmTotal=["1.062,6", "10", "(2,5)"])
    resultado = higienizar_dataframe(df, META)
    assert resultado["viagens"].tolist() == [1234, 5.5, None]
    assert resultado["km_total"].tolist() == [1062.6, 10.0, -2.5]

def teste_colunas_desconhecidas_continuam_texto():
    df = _df(Data=["01/08/2026"], Linha=["01"], Observacao=["1.234,5"])
    assert higienizar_dataframe(df, META)["observacao"].tolist() == ["1.234,5"]

#metadados
def teste_metadados_sao_adicionados_como_colunas_meta():
    resultado = higienizar_dataframe(_df(Data=["01/08/2026"], Linha=["01"], kmTotal=["1"]), META)
    linha = resultado.iloc[0]
    assert linha["meta_tipo_relatorio"] == "mensal_linhas"
    assert linha["meta_periodicidade"] == "mensal"
    assert linha["meta_ano"] == 2026 and linha["meta_mes"] == 8
    assert "meta_semana" not in resultado.columns and "meta_data" not in resultado.columns

def teste_metadados_semana_e_data_aparecem_quando_informados():
    meta = {**META, "semana": 32, "data": "2026-08-15"}
    resultado = higienizar_dataframe(_df(Data=["01/08/2026"], Linha=["01"], kmTotal=["1"]), meta)
    assert resultado["meta_semana"].tolist() == [32]
    assert resultado["meta_data"].tolist() == ["2026-08-15"]

def teste_tabela_somente_com_cabecalho_devolve_vazio_com_metadados():
    resultado = higienizar_dataframe(pd.DataFrame(columns=["Data", "Linha", "kmTotal"]), META)
    assert len(resultado) == 0
    assert list(resultado.columns)[:3] == ["data", "linha", "km_total"]
    assert resultado.filter(like="meta_").shape[1] >= 2

def teste_nao_altera_o_dataframe_de_entrada():
    df = _df(Data=["01/08/2026"], Linha=["01"], kmTotal=["1,5"])
    copia = df.copy()
    higienizar_dataframe(df, META)
    assert df.equals(copia)

def teste_ordem_das_colunas_de_origem_e_preservada():
    df = _df(nrViagens=["1"], Linha=["01"], Data=["01/08/2026"], kmTotal=["2"])
    colunas = [c for c in higienizar_dataframe(df, META).columns if not c.startswith("meta_")]
    assert colunas == ["viagens", "linha", "data", "km_total"]

def teste_resultado_real_de_um_resumo_mensal_com_total_geral():
    df = pd.DataFrame(
        [["01/08/2026", "Sab", "37", "35", "924", "924", "0", "6.889,4", "344,3", "7.233,7"],
         ["Total Geral", "", "", "", "924", "924", "0", "6.889,4", "344,3", "7.233,7"]],
        columns=["Data", "diaSem", "nrVeiculos", "nrMaxVeicFx", "nrViagensProgr", "nrViagensRealiz",
                 "Dif Viagens", "kmProd", "kmImprod", "kmTotal"])
    resultado = higienizar_dataframe(df, META)
    assert len(resultado) == 1
    registro = resultado.iloc[0]
    assert registro["data"] == "2026-08-01" and registro["dia_semana"] == "Sab"
    assert registro["viagens_programadas"] == 924 and registro["km_total"] == 7233.7