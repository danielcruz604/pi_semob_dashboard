import pandas as pd
import pytest
from app.services.transporte_columns import (
    ALIASES_COLUNAS,
    COLUNAS_DECIMAIS,
    COLUNAS_INTEIRAS,
    COLUNAS_NUMERICAS,
    COLUNAS_TEXTO_ESTRITO,
    coluna_eh_inteira,
    coluna_eh_numerica,
    coluna_eh_texto_estrito,
    desduplicar_colunas,
    nome_coluna_base,
    normalizar_nome_coluna,
    normalizar_texto,
)

@pytest.mark.parametrize("valor, esperado", [
    ("  Total  Geral ", "total geral"),
    ("ÇÃO", "cao"),
    ("Ñandú", "nandu"),
    ("Mês Referência", "mes referencia"),
    ("A\tB\nC", "a b c"),
    ("", ""),
    ("   ", ""),
    (None, ""),
    (float("nan"), ""),
    (pd.NA, ""),
    (12, "12"),
    (1.5, "1.5"),
])
def teste_normalizar_texto(valor, esperado):
    assert normalizar_texto(valor) == esperado

@pytest.mark.parametrize("cabecalho, esperado", [
    ("Total Utilização", "total_utilizacao"),
    ("Crédito Circulante", "credito_circulante"),
    ("Ação", "acao"),
    ("  espaços   múltiplos ", "espacos_multiplos"),
    ("Linha  ", "linha"),
    ("kmTotal", "km_total"),
    ("dataHora", "data_hora"),
    ("XMLHttpRequest", "xml_http_request"),
    ("data_hora_ISO", "data_hora_iso"),
    ("NR_VIAGENS", "viagens"),
    ("DATA", "data"),
    ("a__b", "a_b"),

    ("Km/Total (km)", "km_total_km"),
    ("R$ Total", "r_total"),
    ("Nº Veículos", "no_veiculos"),
    ("", ""),
    ("   ", ""),
    ("___", ""),
    (None, ""),
    ("Unnamed: 3", "unnamed_3"),
    (123, "123"),
    (1.5, "1_5"),
])
def teste_normalizar_nome_coluna_texto(cabecalho, esperado):
    assert normalizar_nome_coluna(cabecalho) == esperado

#cabeçalhos reais dos relatórios
@pytest.mark.parametrize("cabecalho, esperado", [
    #Mensal / Quinzenal (resumo geral)
    ("Data", "data"), ("diaSem", "dia_semana"), ("nrVeiculos", "numero_veiculos"),
    ("nrMaxVeicFx", "numero_max_veiculos_faixa"), ("nrViagensProgr", "viagens_programadas"),
    ("nrViagensRealiz", "viagens_realizadas"), ("Dif Viagens", "diferenca_viagens"),
    ("kmProd", "km_produtivos"), ("kmImprod", "km_improdutivos"), ("kmTotal", "km_total"),
    #FCV
    ("manha_p", "viagens_programadas_manha"), ("manha_r", "viagens_realizadas_manha"),
    ("tarde_p", "viagens_programadas_tarde"), ("tarde_r", "viagens_realizadas_tarde"),
    ("noite_p", "viagens_programadas_noite"), ("noite_r", "viagens_realizadas_noite"),
    ("programadas", "viagens_programadas"), ("realizadas", "viagens_realizadas"),
    #Linhas / FxHr / Resumo_FxHr
    ("Linha", "linha"), ("nrViagens", "viagens"), ("Fx_Hor", "faixa_horaria"),
    ("Nr_Veiculos", "numero_veiculos"), ("Nr_Viagens", "viagens"), ("Partidas", "partidas"),
    #Viag_Ninic / NRealiz / NTerm / Viagens
    ("Atendimento", "atendimento"), ("Prefixo", "prefixo"), ("Atividade", "atividade"),
    ("Motorista", "motorista"), ("Sentido", "sentido"), ("Tabela", "tabela"),
    ("statusSaida", "status_saida"), ("statusChegada", "status_chegada"),
    ("inicioProgramado", "inicio_programado"), ("inicioRealizado", "inicio_realizado"),
    ("fimProgramado", "fim_programado"), ("fimRealizado", "fim_realizado"),
    #Passageiros
    ("Mês", "mes_referencia"), ("Dia", "dia"), ("Catraca", "catraca"), ("Antecipados", "antecipados"),
    ("Não Pagantes", "nao_pagantes"), ("Total Passageiros", "total_passageiros"),
    #Saldos
    ("Série", "serie"), ("Créditos transferidos para cartões", "creditos_transferidos_para_cartoes"),
    ("Saldo Final", "saldo_final"), ("Total Vendas", "total_vendas"),
    ("Total Utilização", "total_utilizacao"), ("Crédito Circulante", "credito_circulante"),
])
def teste_cabecalhos_reais_resolvem_para_as_chaves_esperadas_pelo_pipeline(cabecalho, esperado):
    assert normalizar_nome_coluna(cabecalho) == esperado

@pytest.mark.parametrize("tupla, esperado", [
    (("dados", "Linha"), "linha"),
    (("Operação", "Transporte"), ""),
    (("Unnamed: 0_level_0", "Data"), "data"),
    (("km", "km"), "km"),
    (("Data", "Data", "Data"), "data"),
    (("Manhã", "P"), "viagens_programadas_manha"),
    (("A", "B", "C"), "a_b_c"),
    (("", ""), ""),
    ((None, "x"), "x"),
])
def teste_normalizar_nome_coluna_tupla(tupla, esperado):
    assert normalizar_nome_coluna(tupla) == esperado

@pytest.mark.parametrize("chave, alvo", sorted(ALIASES_COLUNAS.items()))
def teste_cada_alias_resolve_para_o_seu_alvo(chave, alvo):
    assert normalizar_nome_coluna(chave) == alvo

@pytest.mark.parametrize("alvo", sorted(set(ALIASES_COLUNAS.values())))
def teste_alvos_de_alias_sao_idempotentes(alvo):
    assert normalizar_nome_coluna(alvo) == alvo

def teste_aliases_nao_tem_chave_vazia_nem_alvo_vazio():
    assert all(k and v for k, v in ALIASES_COLUNAS.items())

@pytest.mark.parametrize("colunas, esperado", [
    (["a", "b", "c"], ["a", "b", "c"]),
    (["a", "a"], ["a", "a_1"]),
    (["a", "a", "a"], ["a", "a_1", "a_2"]),
    (["a", "a", "a_1"], ["a", "a_1", "a_1_1"]),
    (["a_1", "a", "a"], ["a_1", "a", "a_2"]),
    (["x", "x_1", "x"], ["x", "x_1", "x_2"]),
    (["", None, "x"], ["coluna", "coluna_1", "x"]),
    (["  a  ", "a"], ["a", "a_1"]),
    ([], []),
])
def teste_desduplicar_colunas(colunas, esperado):
    assert desduplicar_colunas(colunas) == esperado

@pytest.mark.parametrize("colunas", [
    ["a"] * 10,
    ["a", "a_1", "a", "a_1", "a_2", "a"],
    ["", "", "coluna", "coluna_1"],
])
def teste_desduplicar_sempre_gera_nomes_unicos_e_preserva_o_tamanho(colunas):
    resultado = desduplicar_colunas(colunas)
    assert len(resultado) == len(colunas)
    assert len(set(resultado)) == len(resultado)

@pytest.mark.parametrize("coluna, base, texto, inteira, numerica", [
    ("km_total", "km_total", False, False, True),
    ("km_total_2", "km_total", False, False, True),
    ("linha", "linha", True, False, False),
    ("linha_10", "linha", True, False, False),
    ("viagens", "viagens", False, True, True),
    ("viagens_1", "viagens", False, True, True),
    ("saldo_final", "saldo_final", False, False, True),
    ("a_1_2", "a_1", False, False, False),
    ("ano_2024", "ano", False, False, False),
    ("desconhecida", "desconhecida", False, False, False),
])
def teste_nome_base_e_classificadores(coluna, base, texto, inteira, numerica):
    assert nome_coluna_base(coluna) == base
    assert coluna_eh_texto_estrito(coluna) is texto
    assert coluna_eh_inteira(coluna) is inteira
    assert coluna_eh_numerica(coluna) is numerica

def teste_conjuntos_numericos_sao_disjuntos_e_a_uniao_confere():
    assert not (COLUNAS_INTEIRAS & COLUNAS_DECIMAIS)
    assert COLUNAS_NUMERICAS == COLUNAS_INTEIRAS | COLUNAS_DECIMAIS

def teste_colunas_de_texto_estrito_nao_sao_numericas():
    assert not (COLUNAS_TEXTO_ESTRITO & COLUNAS_NUMERICAS)

CHAVES_INTEIRAS_DO_MAPPER = [
    "numero_veiculos", "numero_max_veiculos_faixa", "viagens_programadas", "viagens_realizadas",
    "viagens_programadas_manha", "viagens_realizadas_manha", "viagens_programadas_tarde",
    "viagens_realizadas_tarde", "viagens_programadas_noite", "viagens_realizadas_noite",
    "viagens", "catraca", "antecipados", "nao_pagantes", "total_passageiros",
]
CHAVES_DECIMAIS_DO_MAPPER = [
    "km_produtivos", "km_improdutivos", "km_total", "creditos_transferidos_para_cartoes",
    "saldo_final", "total_vendas", "total_utilizacao", "credito_circulante",
]
CHAVES_TEXTO_DO_MAPPER = [
    "linha", "atendimento", "prefixo", "atividade", "motorista", "sentido", "tabela", "status_saida",
    "status_chegada", "faixa_horaria", "partidas", "dia_semana", "serie", "mes_referencia", "dia",
]

@pytest.mark.parametrize("chave", CHAVES_INTEIRAS_DO_MAPPER)
def teste_chaves_inteiras_lidas_pelo_mapper_sao_convertidas_pelo_cleaner(chave):
    assert coluna_eh_inteira(chave) and not coluna_eh_texto_estrito(chave)

@pytest.mark.parametrize("chave", CHAVES_DECIMAIS_DO_MAPPER)
def teste_chaves_decimais_lidas_pelo_mapper_sao_convertidas_pelo_cleaner(chave):
    assert chave in COLUNAS_DECIMAIS and not coluna_eh_texto_estrito(chave)

@pytest.mark.parametrize("chave", CHAVES_TEXTO_DO_MAPPER)
def teste_chaves_de_texto_nao_sao_convertidas_em_numero(chave):
    assert coluna_eh_texto_estrito(chave) and not coluna_eh_numerica(chave)

@pytest.mark.parametrize("valor, esperado", [([1, 2], "[1, 2]"), ((1, 2), "(1, 2)")])
def teste_normalizar_texto_com_colecoes_nao_levanta_erro(valor, esperado):
    assert normalizar_texto(valor) == esperado

@pytest.mark.parametrize("cabecalho, esperado", [
    ("km_km", "km"), ("Linha Linha", "linha"), ("total_total", "total"),
    ("km_total_km", "km_total_km"),
    ("a_b", "a_b"),
])
def teste_dois_termos_iguais_colapsam_em_um(cabecalho, esperado):
    assert normalizar_nome_coluna(cabecalho) == esperado