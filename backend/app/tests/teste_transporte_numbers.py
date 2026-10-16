from decimal import Decimal
import numpy as np
import pandas as pd
import pytest
from app.services.transporte_numbers import limpar_numero_brasileiro, tentar_converter_coluna_numerica

D = Decimal

@pytest.mark.parametrize("texto, esperado", [
    ("20.434.667,35", D("20434667.35")),
    ("-3.380,00", D("-3380.00")),
    ("1.062,6", D("1062.6")),
    ("6889,4", D("6889.4")),
    ("0,00", D("0")),
    ("12,5", D("12.5")),
    ("1,234", D("1.234")),
    ("5.168", D("5168")),
    ("1.234.567", D("1234567")),
    ("10.700", D("10700")),
    ("12.5", D("12.5")),
    ("1.23", D("1.23")),
    ("1.2345", D("1.2345")),
    ("1,234.56", D("1234.56")),
    ("0.500", D("0.5")),
    ("0", D("0")),
    ("132", D("132")),
    ("007", D("7")),
    ("000", D("0")),
    ("00,50", D("0.5")),
    ("0010,5", D("10.5")),
    ("+10", D("10")),
    ("-5", D("-5")),
    ("- 5", D("-5")),
    ("12,5%", D("12.5")),
    ("100%", D("100")),
    ("  7  ", D("7")),
    ("1 234,5", D("1234.5")),
    ("\xa01.000,00\xa0", D("1000.00")),
    ("\t5\n", D("5")),
])
def teste_converte_formatos_numericos(texto, esperado):
    resultado = limpar_numero_brasileiro(texto)
    assert isinstance(resultado, Decimal)
    assert resultado == esperado

@pytest.mark.parametrize("texto, esperado", [
    ("(1.500,00)", D("-1500.00")),
    ("(1500)", D("-1500")),
    ("( 1.500,00 )", D("-1500.00")),
    ("(0,5)", D("-0.5")),
    ("-1.500,00", D("-1500.00")),
])
def teste_negativos_entre_parenteses_ou_com_sinal(texto, esperado):
    assert limpar_numero_brasileiro(texto) == esperado

@pytest.mark.parametrize("texto, esperado", [
    ("R$ 1.234,56", D("1234.56")),
    ("R$1.234,56", D("1234.56")),
    ("r$ 10,00", D("10.00")),
    ("RS$ 10,00", D("10.00")),
    ("rs$10", D("10")),
    ("US$ 5.00", D("5.00")),
    ("us$ 1,234.56", D("1234.56")),
    ("-R$ 5,00", D("-5.00")),
    ("R$-5,00", D("-5.00")),
    ("R$ -5,00", D("-5.00")),
    ("(R$ 5,00)", D("-5.00")),
])
def teste_prefixos_de_moeda_com_e_sem_sinal(texto, esperado):
    assert limpar_numero_brasileiro(texto) == esperado

@pytest.mark.parametrize("valor, esperado", [
    (5, D("5")),
    (5.5, D("5.5")),
    (D("3.1"), D("3.1")),
    (np.int64(7), D("7")),
    (np.float64(2.5), D("2.5")),
])
def teste_aceita_tipos_numericos_nativos(valor, esperado):
    assert limpar_numero_brasileiro(valor) == esperado

@pytest.mark.parametrize("inteira", [True, False])
def teste_parametro_inteira_nao_altera_o_valor_convertido(inteira):
    assert limpar_numero_brasileiro("5.168", inteira=inteira) == D("5168")
    assert limpar_numero_brasileiro("12,5", inteira=inteira) == D("12.5")

#nulos e inválidos
@pytest.mark.parametrize("valor", [
    None, "", "   ", "\xa0", "nan", "NaN", "NAN", "None", "none", "null", "NULL", "na", "NA", "N/A", "n/a",
    "-", "--", float("nan"), np.nan, pd.NA, pd.NaT,
])
def teste_nulos_retornam_none(valor):
    assert limpar_numero_brasileiro(valor) is None

@pytest.mark.parametrize("texto", [
    "abc", "12abc", "abc12", "1,2,3", "1e5", "0x10", "Infinity", "R$", "()", "(  )", "%",
    "1.000,00-", "\u22125", "-(5)", "1.000.00", ".5", "5.", ",5", "5,", "1.0.0", "1/2", "12:30", "1;5",
    "--abc", "++", "True", "Total",
])
def teste_textos_invalidos_retornam_none(texto):
    assert limpar_numero_brasileiro(texto) is None

@pytest.mark.parametrize("texto", ["(-5)", "--5", "1.2.3,4", "R$ R$ 5"])
@pytest.mark.xfail(
    reason="Limitação conhecida: notações contraditórias/malformadas são aceitas em vez de rejeitadas "
           "('(-5)' e '--5' viram +5 por dupla negação; '1.2.3,4' vira 123.4; 'R$ R$ 5' vira 5).",
    strict=False,
)
def teste_notacoes_contraditorias_deveriam_ser_rejeitadas(texto):
    assert limpar_numero_brasileiro(texto) is None

#conversão de colunas
@pytest.mark.parametrize("valores, esperado", [
    (["1.234", "5", None, "abc", "(2)", "1,5", ""], [1234, 5, None, None, -2, 1.5, None]),
    (["0", "007", "10.000"], [0, 7, 10000]),
    ([None, pd.NA, "nan"], [None, None, None]),
])
def teste_coluna_inteira(valores, esperado):
    serie = pd.Series(valores, dtype="object")
    resultado = tentar_converter_coluna_numerica(serie, inteira=True)
    assert resultado.tolist() == esperado

def teste_coluna_inteira_mantem_tipo_int_para_valores_inteiros_e_float_para_fracoes():
    resultado = tentar_converter_coluna_numerica(pd.Series(["1.234", "1,5"]), inteira=True)
    assert type(resultado.iloc[0]) is int
    assert type(resultado.iloc[1]) is float

@pytest.mark.parametrize("valores, esperado", [
    (["1.234,5", "10", "-3.380,00", None], [1234.5, 10.0, -3380.0, None]),
    (["1.062,6", "(2,5)", "R$ 3,00"], [1062.6, -2.5, 3.0]),
    (["abc", "", "-"], [None, None, None]),
])
def teste_coluna_decimal(valores, esperado):
    resultado = tentar_converter_coluna_numerica(pd.Series(valores, dtype="object"), inteira=False)
    assert resultado.tolist() == esperado
    assert all(isinstance(v, float) for v in resultado if v is not None)

def teste_coluna_preserva_indice_dtype_e_nao_altera_a_entrada():
    serie = pd.Series(["1,5", "2,5", None], index=[10, 20, 30], dtype="object")
    copia = serie.copy()
    resultado = tentar_converter_coluna_numerica(serie)
    assert list(resultado.index) == [10, 20, 30]
    assert resultado.dtype == object
    assert serie.equals(copia)

@pytest.mark.parametrize("inteira", [True, False])
def teste_coluna_vazia(inteira):
    resultado = tentar_converter_coluna_numerica(pd.Series([], dtype="object"), inteira=inteira)
    assert len(resultado) == 0
    assert resultado.dtype == object

def teste_coluna_com_dtype_string_do_pandas():
    resultado = tentar_converter_coluna_numerica(pd.Series(["1.000", None, "2"], dtype="string"), inteira=True)
    assert resultado.tolist() == [1000, None, 2]

def teste_colecoes_nao_levantam_erro_e_retornam_none():
    assert limpar_numero_brasileiro([1, 2]) is None

def teste_decimal_que_rejeita_o_texto_retorna_none(monkeypatch):
    from decimal import InvalidOperation

    def recusar(texto):
        raise InvalidOperation("simulado")

    monkeypatch.setattr("app.services.transporte_numbers.Decimal", recusar)
    assert limpar_numero_brasileiro("12,5") is None