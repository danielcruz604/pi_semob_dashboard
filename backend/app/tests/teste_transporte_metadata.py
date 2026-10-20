import pytest
from app.services.transporte_metadata import (
    _inferir_periodicidade,
    _normalizar_tipo_relatorio,
    _separar_periodo,
    extrair_metadados_nome_arquivo,
)

CHAVES = {"tipo_relatorio", "periodicidade", "ano", "mes", "semana", "data", "data_inicio", "data_fim"}

def _basico(nome):
    meta = extrair_metadados_nome_arquivo(nome)
    return (meta["tipo_relatorio"], meta["periodicidade"], meta["ano"], meta["mes"], meta["semana"], meta["data"])

#nomes reais (mensal e quinzenal)
@pytest.mark.parametrize("nome, esperado", [
    ("Mensal_202608.html", ("mensal", "mensal", 2026, 8, None, None)),
    ("Mensal_FCV_202608.html", ("mensal_fcv", "mensal", 2026, 8, None, None)),
    ("Mensal_Linhas_202608.html", ("mensal_linhas", "mensal", 2026, 8, None, None)),
    ("Mensal_FxHr_202608.html", ("mensal_fxhr", "mensal", 2026, 8, None, None)),
    ("Mensal_Resumo_FxHr_202608.html", ("mensal_resumo_fxhr", "mensal", 2026, 8, None, None)),
    ("Mensal_Viagens_202607.html", ("mensal_viagens", "mensal", 2026, 7, None, None)),
    ("Mensal_Viag_NRealiz_202608.html", ("mensal_viag_nrealiz", "mensal", 2026, 8, None, None)),
    ("Quinzenal_Viagens_202609.html", ("quinzenal_viagens", "quinzenal", 2026, 9, None, None)),
    ("Quinzenal_Viag_Ninic_202609.html", ("quinzenal_viag_ninic", "quinzenal", 2026, 9, None, None)),
    ("Quinzenal_FCV_202609.html", ("quinzenal_fcv", "quinzenal", 2026, 9, None, None)),
])
def teste_nomes_reais_mensais_e_quinzenais(nome, esperado):
    assert _basico(nome) == esperado

@pytest.mark.parametrize("nome, esperado", [
    ("Passageiros_Mensal.html", ("passageiros_mensal", "mensal", None, None, None, None)),
    ("Passageiros_Quinzenal.html", ("passageiros_quinzenal", "quinzenal", None, None, None, None)),
    ("Passageiros.html", ("passageiros", None, None, None, None, None)),
    ("Saldos.html", ("saldos", None, None, None, None, None)),
    ("Saldos_Mensal.html", ("saldos_mensal", "mensal", None, None, None, None)),
])
def teste_nomes_reais_sem_periodo(nome, esperado):
    assert _basico(nome) == esperado

@pytest.mark.parametrize("nome, esperado", [
    ("Relatorio_20260815.html", ("relatorio", None, 2026, 8, None, "2026-08-15")),
    ("Diario_Linhas_2026-08-15.htm", ("diario_linhas", "diaria", 2026, 8, None, "2026-08-15")),
    ("Diario_Linhas_2026_08_15.html", ("diario_linhas", "diaria", 2026, 8, None, "2026-08-15")),
    ("Semanal_Linhas_2026W32.html", ("semanal_linhas", "semanal", 2026, None, 32, None)),
    ("Semanal_Linhas_2026_32.html", ("semanal_linhas", "semanal", 2026, None, 32, None)),
    ("Semanal_Linhas_2026S5.html", ("semanal_linhas", "semanal", 2026, None, 5, None)),
    ("Semanal_Linhas_2026Semana07.html", ("semanal_linhas", "semanal", 2026, None, 7, None)),
    ("Semanal_202608.html", ("semanal", "semanal", 2026, None, 8, None)),
    ("Mensal_Linhas_2026-08.html", ("mensal_linhas", "mensal", 2026, 8, None, None)),
    ("Mensal-Linhas-202608.html", ("mensal_linhas", "mensal", 2026, 8, None, None)),
])
def teste_data_semana_e_separadores(nome, esperado):
    assert _basico(nome) == esperado

#períodos inválidos não geram metadados
@pytest.mark.parametrize("nome, tipo, periodicidade", [
    ("Mensal_Linhas_202613.html", "mensal_linhas_202613", "mensal"),      # mês 13
    ("Mensal_Linhas_202600.html", "mensal_linhas_202600", "mensal"),      # mês 00
    ("Mensal_20261345.html", "mensal_20261345", "mensal"),                # data impossível
    ("Diaria_20260230.html", "diaria_20260230", "diaria"),                # 30 de fevereiro
    ("Semanal_Linhas_2026_54.html", "semanal_linhas_2026_54", "semanal"),  # semana 54
    ("Semanal_Linhas_2026_00.html", "semanal_linhas_2026_00", "semanal"),  # semana 0
    ("Linhas_202608_final.html", "linhas_202608_final", None),            # período não está no fim
])
def teste_periodo_invalido_ou_fora_do_fim_nao_gera_ano_mes_semana_nem_data(nome, tipo, periodicidade):
    assert _basico(nome) == (tipo, periodicidade, None, None, None, None)

@pytest.mark.parametrize("nome", [
    "MENSAL_LINHAS_202608.HTML",
    "mensal_linhas_202608.htm",
    "C:\\relatorios\\Mensal_Linhas_202608.html",
    "/tmp/uploads/Mensal_Linhas_202608.htm",
    "../../etc/Mensal_Linhas_202608.html",
    "Mensal_Linhas_202608",
    "  Mensal_Linhas_202608.html  ",
])
def teste_nome_com_caixa_caminho_espacos_ou_sem_extensao(nome):
    assert _basico(nome) == ("mensal_linhas", "mensal", 2026, 8, None, None)

@pytest.mark.xfail(reason="Limitação conhecida: o período só é reconhecido após '_' ou '-'; com espaços "
                          "('Mensal Linhas 202608.html') ano/mês não são extraídos.", strict=False)
def teste_periodo_separado_por_espaco_deveria_ser_reconhecido():
    assert _basico("Mensal Linhas 202608.html") == ("mensal_linhas", "mensal", 2026, 8, None, None)

def teste_acentos_sao_removidos_do_tipo():
    assert _basico("Relatório_Mensal_202608.html")[:2] == ("relatorio_mensal", "mensal")

@pytest.mark.parametrize("nome", ["", ".html", ".htm", "   "])
def teste_nome_degenerado_nao_levanta_excecao(nome):
    meta = extrair_metadados_nome_arquivo(nome)
    assert meta["tipo_relatorio"] == ""
    assert meta["ano"] is None and meta["mes"] is None

@pytest.mark.parametrize("nome", ["Mensal_Linhas_202608.html", "Passageiros.html", "x"])
def teste_retorno_sempre_tem_todas_as_chaves_e_intervalo_vazio(nome):
    meta = extrair_metadados_nome_arquivo(nome)
    assert set(meta) == CHAVES
    assert meta["data_inicio"] is None and meta["data_fim"] is None

@pytest.mark.parametrize("nome, esperado", [
    ("Mensal Linhas", "mensal_linhas"),
    ("mensal--linhas__x", "mensal_linhas_x"),
    ("Relatório Diário!", "relatorio_diario"),
    ("_x_", "x"),
    ("", ""),
])
def teste_normalizar_tipo_relatorio(nome, esperado):
    assert _normalizar_tipo_relatorio(nome) == esperado

@pytest.mark.parametrize("tipo, esperado", [
    ("mensal_linhas", "mensal"), ("mes_fcv", "mensal"),
    ("diario_x", "diaria"), ("diaria", "diaria"), ("diariamente", "diaria"),
    ("semanal_x", "semanal"), ("semana", "semanal"),
    ("quinzenal", "quinzenal"), ("quinzena_x", "quinzenal"),
    ("linhas", None), ("", None),
    ("diario_mensal", "diaria"),        # precedência: diária > semanal > quinzenal > mensal
    ("semanal_mensal", "semanal"),
    ("quinzenal_mensal", "quinzenal"),
])
def teste_inferir_periodicidade(tipo, esperado):
    assert _inferir_periodicidade(tipo) == esperado

@pytest.mark.parametrize("nome_base, periodicidade, esperado", [
    ("Mensal_202608", "mensal", ("Mensal", 2026, 8, None, None)),
    ("Rel_20260815", None, ("Rel", 2026, 8, None, "2026-08-15")),
    ("Semanal_2026W07", "semanal", ("Semanal", 2026, None, 7, None)),
    ("Rel", None, ("Rel", None, None, None, None)),
    ("", None, ("", None, None, None, None)),
])
def teste_separar_periodo(nome_base, periodicidade, esperado):
    assert _separar_periodo(nome_base, periodicidade) == esperado