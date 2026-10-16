#Amostras HTML em memória para os testes.
#A estrutura imita os relatórios reais do Smart Report: charset Cp1252, tabela de rodapé
#"Gerado por Smart Report" com 2 colunas e class="data", tabelas de dados com <th> soltos
#(ou dentro de <tr>), linhas de total, entidades (&gt;, &nbsp;) e <br> em cabeçalhos.
from typing import NamedTuple, Optional, Sequence

CODECS = {
    "cp1252": "cp1252", "windows-1252": "cp1252",
    "latin-1": "latin-1", "iso-8859-1": "latin-1",
    "utf-8": "utf-8", "utf8": "utf-8",
}

def tabela(cabecalhos: Sequence[str], linhas: Sequence[Sequence[str]],
           classe: Optional[str] = "data", th_em_tr: bool = False, aspas: str = "'") -> str:
    #Monta uma <table>. Células são inseridas cruas (permitem &gt;, &nbsp;, <br>).
    ths = "".join(f"<th>{h}</th>" for h in cabecalhos)
    cabecalho = f"<tr>{ths}</tr>" if th_em_tr else ths
    corpo = "".join(
        f"<tr class='{'even' if i % 2 else 'odd'}'>" + "".join(f"<td>{c}</td>" for c in linha) + "</tr>\n"
        for i, linha in enumerate(linhas)
    )
    atributo = "" if classe is None else f" class={aspas}{classe}{aspas}" if aspas else f" class={classe}"
    return f"<table{atributo}>\n{cabecalho}\n{corpo}</table>\n"

RODAPE_SMART_REPORT = (
    "<table class='info'><tr><td>Relatório de Transporte</td></tr></table>\n"
    "<table class='data'>\n<th><a href='http://www.smartdatasource.com.br'>SmartDataSource.com.br</a></th>"
    "<th>Horário</th>\n<tr><td>Gerado por Smart Report</td><td>04/09/2026 08:00</td></tr>\n</table>\n"
)

def documento(corpo: str, charset: Optional[str] = "Cp1252", rodape: bool = True) -> str:
    meta = f'<meta http-equiv="Content-Type" content="text/html; charset={charset}">' if charset else ""
    return (
        f'<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN">\n<html><head>{meta}'
        "<style>table.data td{border:1px solid #000}</style></head><body>\n"
        f"{RODAPE_SMART_REPORT if rodape else ''}{corpo}</body></html>\n"
    )

def montar_html(tabelas: Sequence[str], charset: Optional[str] = "Cp1252",
                codec: Optional[str] = None, rodape: bool = True) -> bytes:
    #Gera o arquivo em bytes. `codec` força uma codificação diferente da declarada (arquivo corrompido).
    texto = documento("".join(tabelas), charset=charset, rodape=rodape)
    codec = codec or CODECS.get((charset or "utf-8").lower(), "utf-8")
    return texto.encode(codec, errors="replace")

#cabeçalhos reais
CAB_RESUMO = ["Data", "diaSem", "nrVeiculos", "nrMaxVeicFx", "nrViagensProgr", "nrViagensRealiz",
              "Dif Viagens", "kmProd", "kmImprod", "kmTotal"]
CAB_FCV = ["Data", "manha_p", "manha_r", "tarde_p", "tarde_r", "noite_p", "noite_r", "programadas", "realizadas"]
CAB_LINHAS = ["Data", "Linha", "kmTotal", "nrViagens"]
CAB_FXHR = ["Data", "Linha", "Fx_Hor", "Nr_Veiculos", "Nr_Viagens", "Partidas"]
CAB_RESUMO_FXHR = ["Data", "Fx_Hor", "Nr_Veiculos", "Nr_Viagens"]
CAB_OCORRENCIAS = ["Data", "Linha", "Atendimento", "Prefixo", "Atividade", "Motorista", "Sentido", "Tabela",
                   "statusSaida", "statusChegada", "inicioProgramado", "inicioRealizado",
                   "fimProgramado", "fimRealizado", "kmProd"]
CAB_PASSAGEIROS = ["Mês", "Dia", "Catraca", "Antecipados", "Não Pagantes", "Total Passageiros"]
CAB_SALDOS_CREDITOS = ["Mês", "Dia", "Série", "Créditos transferidos<br>para cartões", "Saldo Final"]
CAB_SALDOS_MOVIMENTOS = ["Mês", "Dia", "Total Vendas", "Total Utilização", "Crédito Circulante"]
CAB_VIAGENS = ["Data", "Linha", "Prefixo", "Atividade", "Sentido", "Fx_Hor", "inicioRealizado",
               "fimRealizado", "kmProd", "kmImprod", "kmTotal"]

#linhas de dados
LINHAS_RESUMO = [
    ["01/08/2026", "Sab", "37", "35", "924", "924", "0", "6.889,4", "344,3", "7.233,7"],
    ["02/08/2026", "Dom", "30", "28", "800", "790", "10", "5.000,5", "300,25", "5.300,75"],
    ["03/08/2026", "Seg", "40", "38", "1.000", "1.000", "0", "7.000,0", "350,0", "7.350,0"],
    ["Total Geral", "", "", "", "2.724", "2.714", "10", "18.889,9", "994,55", "19.884,45"],
]
LINHAS_FCV = [
    ["01/08/2026", "372", "372", "303", "303", "249", "249", "924", "924"],
    ["02/08/2026", "320", "310", "280", "280", "200", "200", "800", "790"],
    ["03/08/2026", "400", "400", "350", "350", "250", "250", "1.000", "1.000"],
    ["", "1.092", "1.082", "933", "933", "699", "699", "2.724", "2.714"],
]
LINHAS_LINHAS = [
    ["01/08/2026", "01", "1.062,6", "132"],
    ["01/08/2026", "02", "980,4", "118"],
    ["02/08/2026", "01", "1.010,0", "128"],
    ["02/08/2026", "10", "450,5", "60"],
    ["", "", "3.503,5", "438"],
]
LINHAS_FXHR = [
    ["01/08/2026", "01", "4hs", "2", "3", "34 &gt; 57 &gt; 59"],
    ["01/08/2026", "01", "5hs", "2", "4", "19 &gt; 20 &gt; 44 &gt; 45"],
    ["01/08/2026", "02", "0hs", "1", "1", "10"],
    ["02/08/2026", "01", "23hs", "3", "2", "5 &gt; 50"],
    ["", "", "", "", "10", ""],
]
LINHAS_RESUMO_FXHR = [
    ["01/08/2026", "4hs", "5", "7"],
    ["01/08/2026", "0hs", "5", "7"],
    ["", "", "", "14"],
]
LINHAS_NREALIZ = [
    ["02/08/2026", "04", "B. SANTA PAULA SENTIDO ESTAÇÃO", "", "Viagem Normal", "667", "I", "1B",
     "", "", "2026-08-02 19:10:00", "", "2026-08-02 19:40:00", "", "0"],
    ["03/08/2026", "01", "ESTAÇÃO SENTIDO B. SANTA MARIA", "", "Viagem Normal", "668", "V", "2A",
     "", "", "2026-08-03 06:00:00", "", "2026-08-03 06:35:00", "", "0"],
]
LINHAS_NTERM = [
    ["05/08/2026", "02", "CENTRO SENTIDO BAIRRO", "1444", "Viagem Normal", "77", "I", "3A",
     "RG", "RG", "2026-08-05 10:00:00", "2026-08-05 10:02:00", "2026-08-05 10:40:00", "", "5,5"],
]
LINHAS_PASSAGEIROS = [
    ["2026-08", "01", "5.168", "676", "10.700", "16.544"],
    ["2026-08", "02", "4.000", "500", "8.000", "12.500"],
    ["2026-08", "Total Mês", "9.168", "1.176", "18.700", "29.044"],
    ["2026-09", "01", "3.000", "400", "7.000", "10.400"],
    ["2026-09", "Total Mês", "3.000", "400", "7.000", "10.400"],
]
LINHAS_SALDOS_CREDITOS = [
    ["2026-08", "02", "1", "4.805,00", "20.434.667,35"],
    ["2026-08", "03", "1", "1.000,00", "20.435.667,35"],
    ["2026-08", "Total Mês", "", "5.805,00", "&nbsp;"],
]
LINHAS_SALDOS_MOVIMENTOS = [
    ["2026-08", "01", "0,00", "3.380,00", "-3.380,00"],
    ["2026-08", "02", "4.900,00", "1.980,00", "2.920,00"],
    ["&nbsp;", "Total Acumulado", "4.900,00", "5.360,00", "-460,00"],
]
LINHAS_VIAGENS = [
    ["01/08/2026", "01", "1444", "Viagem Normal", "I", "4", "2026-08-01 04:34:00", "2026-08-01 05:10:00",
     "6,5", "0", "6,5"],
    ["01/08/2026", "", "3361", "Improdutivas", "", "0", "", "", "0", "0,3", "0,3"],
    ["", "", "", "", "", "0", "", "", "6,5", "0,3", "6,8"],
]

#arquivos válidos
class Amostra(NamedTuple):
    arquivo: str
    conteudo: bytes
    tipo: str                 # tipo_relatorio esperado
    categoria: str            # categoria de persistência (ou 'sem_colecao')
    colecao: Optional[str]    # coleção MongoDB de destino (None = não persiste)
    registros: int            # registros válidos do 1º conjunto
    afetados: Optional[int]   # documentos gravados na 1ª persistência

def _amostras() -> dict:
    return {
        "resumo": Amostra("Mensal_202608.html", montar_html([tabela(CAB_RESUMO, LINHAS_RESUMO)]),
                          "mensal", "resumo_geral", "viagensSistema", 3, 3),
        "fcv": Amostra("Mensal_FCV_202608.html", montar_html([tabela(CAB_FCV, LINHAS_FCV)]),
                       "mensal_fcv", "resumo_geral", "viagensSistema", 3, 3),
        "linhas": Amostra("Mensal_Linhas_202608.html", montar_html([tabela(CAB_LINHAS, LINHAS_LINHAS)]),
                          "mensal_linhas", "linhas", "viagensLinhas", 4, 4),
        "fxhr": Amostra("Mensal_FxHr_202608.html", montar_html([tabela(CAB_FXHR, LINHAS_FXHR)]),
                        "mensal_fxhr", "fxhr", "viagensHorario", 4, 4),
        "nrealiz": Amostra("Mensal_Viag_NRealiz_202608.html",
                           montar_html([tabela(CAB_OCORRENCIAS, LINHAS_NREALIZ)]),
                           "mensal_viag_nrealiz", "ocorrencias", "viagensOcorrencias", 2, 2),
        "nterm": Amostra("Mensal_Viag_NTerm_202608.html", montar_html([tabela(CAB_OCORRENCIAS, LINHAS_NTERM)]),
                         "mensal_viag_nterm", "ocorrencias", "viagensOcorrencias", 1, 1),
        "passageiros": Amostra("Passageiros_Mensal.html",
                               montar_html([tabela(CAB_PASSAGEIROS, LINHAS_PASSAGEIROS, th_em_tr=True)]),
                               "passageiros_mensal", "passageiros", "passageirosSistema", 3, 3),
        "saldos": Amostra("Saldos_Mensal.html", montar_html([
            tabela(CAB_SALDOS_CREDITOS, LINHAS_SALDOS_CREDITOS, th_em_tr=True),
            tabela(CAB_SALDOS_MOVIMENTOS, LINHAS_SALDOS_MOVIMENTOS, th_em_tr=True)]),
            "saldos_mensal", "saldos", "financeiroSistema", 2, 3),
    }

AMOSTRAS = _amostras()

#Relatórios reconhecidos, mas sem coleção de destino definida
AMOSTRAS_SEM_COLECAO = {
    "resumo_fxhr": Amostra("Mensal_Resumo_FxHr_202608.html",
                           montar_html([tabela(CAB_RESUMO_FXHR, LINHAS_RESUMO_FXHR)]),
                           "mensal_resumo_fxhr", "resumo_fxhr", None, 2, None),
    "viagens": Amostra("Mensal_Viagens_202608.html", montar_html([tabela(CAB_VIAGENS, LINHAS_VIAGENS)]),
                       "mensal_viagens", "viagens_detalhe", None, 2, None),
}

#casos limite
HTML_VAZIO = b""
HTML_SEM_TABELAS = b"<html><body><p>Sem tabelas aqui</p></body></html>"
HTML_SO_TABELA_INFO = montar_html([tabela(["A", "B", "C"], [["1", "2", "3"]], classe="info")], rodape=False)
HTML_SO_RODAPE = montar_html([], rodape=True)
HTML_CLASSE_EM_ATRIBUTO_DATA = (
    b"<html><body><table data-class='data'><tr><th>Data</th><th>Linha</th><th>kmTotal</th></tr>"
    b"<tr><td>01/08/2026</td><td>01</td><td>1</td></tr></table></body></html>"
)
HTML_SEM_FECHAMENTO = (
    b"<html><body><table class='data'><th>Data</th><th>Linha</th><th>kmTotal</th>"
    b"<tr><td>01/08/2026</td><td>01</td><td>1</td></tr>"
)
HTML_APENAS_TOTAIS = montar_html([tabela(CAB_LINHAS, [["Total Geral", "", "3.503,5", "438"], ["", "", "1,0", "2"]])])
HTML_SEM_REGISTROS = montar_html([tabela(CAB_LINHAS, [])])
HTML_COLUNAS_DESORDENADAS = montar_html([tabela(
    ["nrViagens", "Linha", "Data", "kmTotal"],
    [["132", "01", "01/08/2026", "1.062,6"], ["118", "02", "01/08/2026", "980,4"]])])
HTML_COLUNAS_AUSENTES = montar_html([tabela(["Data", "Linha", "nrViagens"], [["01/08/2026", "01", "132"]])])
HTML_COLUNAS_DUPLICADAS = montar_html([tabela(
    ["Data", "Linha", "Linha", "kmTotal"], [["01/08/2026", "01", "02", "1,5"]])])
HTML_CABECALHO_VAZIO = montar_html([tabela(
    ["Data", "", "Linha", "kmTotal"], [["01/08/2026", "lixo", "01", "1,5"]])])
HTML_CLASSE_SEM_ASPAS = montar_html([tabela(CAB_LINHAS, LINHAS_LINHAS, aspas="")])
HTML_CLASSE_MULTIPLA = montar_html([tabela(CAB_LINHAS, LINHAS_LINHAS, classe="zebra data")])
HTML_CLASSE_ASPAS_DUPLAS = montar_html([tabela(CAB_LINHAS, LINHAS_LINHAS, aspas='"')])
HTML_DOIS_DOCUMENTOS = (
    montar_html([tabela(CAB_LINHAS, LINHAS_LINHAS)]) + montar_html([tabela(CAB_LINHAS, LINHAS_LINHAS[:2] + LINHAS_LINHAS[-1:])])
)

_TAB_ACENTOS = tabela(CAB_OCORRENCIAS, LINHAS_NREALIZ)  # contém ESTAÇÃO
HTML_UTF8 = montar_html([_TAB_ACENTOS], charset="utf-8")
HTML_SEM_CHARSET_UTF8 = montar_html([_TAB_ACENTOS], charset=None, codec="utf-8")
HTML_CP1252_DECLARADO_UTF8 = montar_html([_TAB_ACENTOS], charset="utf-8", codec="cp1252")
HTML_LATIN1 = montar_html([_TAB_ACENTOS], charset="ISO-8859-1")
HTML_BYTE_INDEFINIDO_CP1252 = montar_html([_TAB_ACENTOS]).replace(b"PAULA", b"PA\x81ULA")  # 0x81 é indefinido no cp1252
HTML_CHARSET_EXOTICO = montar_html([tabela(CAB_LINHAS, LINHAS_LINHAS)], charset="Shift_JIS", codec="cp1252")

#massa real (opcional)
LIMITE_ARQUIVO_PEQUENO = 3 * 1024 * 1024

def arquivos_reais() -> list:
    #HTMLs reais em TRANSPORTE_DADOS_DIR (ignora os > 3 MB, salvo TRANSPORTE_TESTAR_GRANDES=1).
    import os
    from pathlib import Path

    pasta = os.getenv("TRANSPORTE_DADOS_DIR")
    if not pasta or not Path(pasta).is_dir():
        return []
    grandes = os.getenv("TRANSPORTE_TESTAR_GRANDES") == "1"
    return [p for p in sorted(Path(pasta).rglob("*.htm*")) if grandes or p.stat().st_size <= LIMITE_ARQUIVO_PEQUENO]

def parametros_reais() -> list:
    #Lista de pytest.param para @parametrize; vira um único teste 'skip' quando não há dados reais.
    import os
    from pathlib import Path

    import pytest

    arquivos = arquivos_reais()
    if not arquivos:
        return [pytest.param(None, marks=pytest.mark.skip(reason="defina TRANSPORTE_DADOS_DIR (HTMLs reais)"),
                             id="sem-dados-reais")]
    raiz = Path(os.environ["TRANSPORTE_DADOS_DIR"])
    return [pytest.param(p, id=p.relative_to(raiz).as_posix()) for p in arquivos]