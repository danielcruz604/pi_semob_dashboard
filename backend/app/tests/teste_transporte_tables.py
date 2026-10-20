import pandas as pd
import pytest
import amostras_html as A
from app.services import transporte_tables as T
from app.services.transporte_tables import (
    _classes_tabela,
    _detectar_encoding,
    _numero_colunas_cabecalho,
    _numero_colunas_maximo,
    _parsear_tabela,
    _reparar_cabecalho_tabela,
    ler_tabelas_html,
    preservar_texto,
)

#preservar_texto
@pytest.mark.parametrize("valor, esperado", [
    ("01", "01"), ("  x  ", "x"), ("", None), ("   ", None), ("\xa0", None), (None, None),
    (float("nan"), None), (pd.NA, None), (5, "5"), (1.5, "1.5"), ("N/A", "N/A"), ("nan", "nan"),
])
def teste_preservar_texto(valor, esperado):
    assert preservar_texto(valor) == esperado

#_classes_tabela
@pytest.mark.parametrize("atributos, esperado", [
    (b" class='data'", {"data"}),
    (b' class="data"', {"data"}),
    (b" class=data", {"data"}),
    (b' class="zebra data"', {"zebra", "data"}),
    (b' CLASS="DATA"', {"data"}),
    (b" class = 'data'", {"data"}),
    (b' id="x" class="info" width="1"', {"info"}),
    (b' data-class="data"', set()),          # atributo data-class não é class
    (b' id="x"', set()),
    (b"", set()),
])
def teste_classes_tabela(atributos, esperado):
    assert _classes_tabela(atributos) == esperado

#_detectar_encoding
@pytest.mark.parametrize("cabecalho, esperado", [
    (b'<meta charset="Cp1252">', ["cp1252", "utf-8", "latin-1"]),
    (b"<meta charset=windows-1252>", ["cp1252", "utf-8", "latin-1"]),
    (b'<meta content="text/html; charset=ISO-8859-1">', ["latin-1", "utf-8", "cp1252"]),
    (b"<meta charset='latin1'>", ["latin-1", "utf-8", "cp1252"]),
    (b'<meta charset="utf-8">', ["utf-8", "cp1252", "latin-1"]),
    (b"<meta charset=UTF8>", ["utf-8", "cp1252", "latin-1"]),
    (b'<meta charset="Shift_JIS">', ["utf-8", "cp1252", "latin-1"]),   # não suportado: ignorado
    (b"<html></html>", ["utf-8", "cp1252", "latin-1"]),                # sem declaração
    (b"", ["utf-8", "cp1252", "latin-1"]),
])
def teste_detectar_encoding_ordem_de_tentativas(cabecalho, esperado):
    assert _detectar_encoding(cabecalho) == esperado

def teste_detectar_encoding_so_olha_os_primeiros_8kb():
    conteudo = b"x" * 9000 + b'<meta charset="latin-1">'
    assert _detectar_encoding(conteudo)[0] == "utf-8"

#cabeçalho
def teste_reparar_cabecalho_envolve_th_soltos_em_tr():
    fragmento = b"<table class='data'>\n<th>A</th><th>B</th>\n<tr><td>1</td></tr></table>"
    corrigido = _reparar_cabecalho_tabela(fragmento)
    assert b"<tr><th>A</th><th>B</th>\n</tr>" in corrigido

def teste_reparar_cabecalho_nao_altera_th_que_ja_estao_em_tr():
    fragmento = b"<table class='data'><tr><th>A</th><th>B</th></tr><tr><td>1</td></tr></table>"
    assert _reparar_cabecalho_tabela(fragmento) == fragmento

def teste_reparar_cabecalho_e_idempotente():
    fragmento = b"<table class='data'><th>A</th><th>B</th><tr><td>1</td></tr></table>"
    uma_vez = _reparar_cabecalho_tabela(fragmento)
    assert _reparar_cabecalho_tabela(uma_vez) == uma_vez

@pytest.mark.parametrize("fragmento, esperado", [
    (b"<table><tr><th>A</th><th>B</th><th>C</th></tr></table>", 3),
    (b"<table><th>A</th><th>B</th><tr><td>1</td><td>2</td></tr></table>", 2),   # th soltos (sem tr)
    (b"<table><tr><td>1</td></tr></table>", 0),                                  # sem th
    (b"<table></table>", 0),
    (b"<table><tr><TH>A</TH><TH>B</TH></tr></table>", 2),                        # maiúsculas
])
def teste_numero_colunas_cabecalho(fragmento, esperado):
    assert _numero_colunas_cabecalho(fragmento) == esperado

@pytest.mark.parametrize("fragmento, esperado", [
    (b"<table><tr><th>A</th><th>B</th></tr><tr><td>1</td><td>2</td><td>3</td></tr></table>", 3),  # corpo mais largo
    (b"<table><tr><th>A</th><th>B</th><th>C</th></tr><tr><td>1</td></tr></table>", 3),            # cabeçalho mais largo
    (b"<table><tr><td>1</td><td>2</td><tr><td>3</td></table>", 2),                                # sem </tr>
    (b"<table></table>", 0),
])
def teste_numero_colunas_maximo(fragmento, esperado):
    assert _numero_colunas_maximo(fragmento) == esperado

#_parsear_tabela
def teste_parsear_tabela_preserva_zeros_a_esquerda_e_textos_como_str():
    fragmento = A.tabela(["Data", "Linha", "kmTotal"], [["01/08/2026", "01", "1.062,6"], ["02/08/2026", "007", "N/A"]],
                         th_em_tr=True).encode()
    df = _parsear_tabela(fragmento, "utf-8")
    assert df["Linha"].tolist() == ["01", "007"]
    assert df["kmTotal"].tolist() == ["1.062,6", "N/A"]
    assert df["Data"].tolist() == ["01/08/2026", "02/08/2026"]

def teste_parsear_tabela_preserva_zeros_em_coluna_alem_do_cabecalho():
    fragmento = b"<table class='data'><tr><th>A</th><th>B</th></tr><tr><td>1</td><td>2</td><td>007</td></tr></table>"
    df = _parsear_tabela(fragmento, "utf-8")
    assert "007" in df.iloc[:, 2].astype(str).tolist()

def teste_parsear_tabela_decodifica_entidades_e_br():
    fragmento = A.tabela(["Mês", "Dia", "Créditos transferidos<br>para cartões"], [["2026-08", "01", "34 &gt; 57"]], th_em_tr=True).encode("cp1252")
    df = _parsear_tabela(fragmento, "cp1252")
    assert df.iloc[0, 2] == "34 > 57"
    assert "Créditos transferidos" in str(df.columns[2]) and "para cartões" in str(df.columns[2])

def teste_parsear_tabela_decodificacao_estrita_levanta_unicodedecodeerror():
    with pytest.raises(UnicodeDecodeError):
        _parsear_tabela(b"<table><tr><th>A</th></tr><tr><td>\xe7</td></tr></table>", "utf-8")

def teste_parsear_tabela_sem_resultado_do_pandas_levanta_valueerror(monkeypatch):
    monkeypatch.setattr(T.pd, "read_html", lambda *a, **k: [])
    with pytest.raises(ValueError, match="não contém dados legíveis"):
        _parsear_tabela(b"<table><tr><th>A</th><th>B</th><th>C</th></tr></table>", "utf-8")

#ler_tabelas_html: sucesso
def teste_le_tabela_com_th_soltos_estilo_mensal(html_linhas):
    (df,) = ler_tabelas_html(html_linhas)
    assert list(df.columns) == A.CAB_LINHAS
    assert len(df) == len(A.LINHAS_LINHAS)          # inclui a linha de total (a limpeza é do cleaner)
    assert df.iloc[0].tolist() == ["01/08/2026", "01", "1.062,6", "132"]

def teste_le_tabela_com_th_dentro_de_tr_estilo_passageiros(html_passageiros):
    (df,) = ler_tabelas_html(html_passageiros)
    assert list(df.columns) == A.CAB_PASSAGEIROS
    assert len(df) == len(A.LINHAS_PASSAGEIROS)

def teste_le_duas_tabelas_de_dados_e_ignora_info_e_rodape(html_saldos):
    tabelas = ler_tabelas_html(html_saldos)
    assert [len(t) for t in tabelas] == [len(A.LINHAS_SALDOS_CREDITOS), len(A.LINHAS_SALDOS_MOVIMENTOS)]
    assert "Gerado por Smart Report" not in tabelas[0].to_string()

def teste_cabecalho_com_br_gera_nome_legivel(html_saldos):
    colunas = [str(c) for c in ler_tabelas_html(html_saldos)[0].columns]
    assert any("Créditos transferidos" in c and "cartões" in c for c in colunas)

def teste_le_documentos_concatenados():
    tabelas = ler_tabelas_html(A.HTML_DOIS_DOCUMENTOS)
    assert [len(t) for t in tabelas] == [5, 3]

def teste_preserva_entidade_gt_nas_partidas(html_fxhr):
    (df,) = ler_tabelas_html(html_fxhr)
    assert df["Partidas"].iloc[0] == "34 > 57 > 59"

@pytest.mark.parametrize("conteudo", [A.HTML_CLASSE_SEM_ASPAS, A.HTML_CLASSE_MULTIPLA, A.HTML_CLASSE_ASPAS_DUPLAS],
                         ids=["sem-aspas", "classe-multipla", "aspas-duplas"])
def teste_reconhece_variacoes_do_atributo_class(conteudo):
    (df,) = ler_tabelas_html(conteudo)
    assert list(df.columns) == A.CAB_LINHAS

def teste_tabela_somente_com_cabecalho_e_aceita():
    (df,) = ler_tabelas_html(A.HTML_SEM_REGISTROS)
    assert list(df.columns) == A.CAB_LINHAS and len(df) == 0

def teste_tabela_com_cabecalho_vazio_gera_coluna_unnamed():
    (df,) = ler_tabelas_html(A.HTML_CABECALHO_VAZIO)
    assert any(str(c).lower().startswith("unnamed") for c in df.columns)

#ler_tabelas_html: encodings
def teste_cp1252_declarado_preserva_acentos():
    (df,) = ler_tabelas_html(A.AMOSTRAS["nrealiz"].conteudo)
    assert df["Atendimento"].iloc[0] == "B. SANTA PAULA SENTIDO ESTAÇÃO"

@pytest.mark.parametrize("conteudo", [A.HTML_UTF8, A.HTML_SEM_CHARSET_UTF8, A.HTML_CP1252_DECLARADO_UTF8,
                                      A.HTML_LATIN1],
                         ids=["utf8", "sem-charset-utf8", "cp1252-declarado-utf8", "latin1"])
def teste_acentos_corretos_em_varios_encodings_e_declaracoes(conteudo):
    (df,) = ler_tabelas_html(conteudo)
    assert "ESTAÇÃO" in df["Atendimento"].iloc[0]

def teste_charset_nao_suportado_e_ignorado_e_usa_a_ordem_padrao():
    (df,) = ler_tabelas_html(A.HTML_CHARSET_EXOTICO)
    assert list(df.columns) == A.CAB_LINHAS

def teste_byte_indefinido_no_cp1252_cai_no_fallback_latin1_sem_levantar_erro():
    (df,) = ler_tabelas_html(A.HTML_BYTE_INDEFINIDO_CP1252)
    assert "\x81" in df["Atendimento"].iloc[0]
    assert "ESTAÇÃO" in df["Atendimento"].iloc[0]

#ler_tabelas_html: erros
@pytest.mark.parametrize("conteudo, trecho", [
    (A.HTML_VAZIO, "vazio"),
    (A.HTML_SEM_TABELAS, "Nenhuma tabela operacional"),
    (A.HTML_SO_TABELA_INFO, "Nenhuma tabela operacional"),
    (A.HTML_SO_RODAPE, "Nenhuma tabela operacional"),                 # só a tabela de 2 colunas
    (A.HTML_CLASSE_EM_ATRIBUTO_DATA, "Nenhuma tabela operacional"),   # data-class não conta
    (A.HTML_SEM_FECHAMENTO, "Nenhuma tabela operacional"),            # <table> sem </table>
    (b"\x00\x01\x02 lixo binario \xff\xfe", "Nenhuma tabela operacional"),
])
def teste_entradas_sem_dados_operacionais_levantam_valueerror(conteudo, trecho):
    with pytest.raises(ValueError, match=trecho):
        ler_tabelas_html(conteudo)

def teste_tabela_data_com_menos_de_tres_colunas_e_ignorada():
    html = A.montar_html([A.tabela(["A", "B"], [["1", "2"]])], rodape=False)
    with pytest.raises(ValueError, match="Nenhuma tabela operacional"):
        ler_tabelas_html(html)

@pytest.mark.parametrize("excecao", [ValueError("falhou"), ImportError("sem lxml"), IndexError("fora")])
def teste_falha_de_parsing_em_todos_os_encodings_vira_valueerror_com_detalhes(monkeypatch, html_linhas, excecao):
    def falhar(*args, **kwargs):
        raise excecao

    monkeypatch.setattr(T, "_parsear_tabela", falhar)
    with pytest.raises(ValueError, match="Não foi possível interpretar") as info:
        ler_tabelas_html(html_linhas)
    mensagem = str(info.value)
    assert "cp1252" in mensagem and "utf-8" in mensagem and "latin-1" in mensagem

def teste_falha_no_primeiro_encoding_tenta_o_proximo(monkeypatch, html_linhas):
    tentativas = []
    original = T._parsear_tabela

    def primeira_falha(fragmento, encoding):
        tentativas.append(encoding)
        if len(tentativas) == 1:
            raise UnicodeDecodeError("utf-8", b"", 0, 1, "simulado")
        return original(fragmento, encoding)

    monkeypatch.setattr(T, "_parsear_tabela", primeira_falha)
    (df,) = ler_tabelas_html(html_linhas)
    assert tentativas[:2] == ["cp1252", "utf-8"] and len(df) == len(A.LINHAS_LINHAS)

def teste_preservar_texto_com_colecoes_nao_levanta_erro():
    assert preservar_texto([1, 2]) == "[1, 2]"