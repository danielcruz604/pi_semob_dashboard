import io
import logging
import pytest
from fastapi import HTTPException
from pymongo.errors import (
    AutoReconnect,
    BulkWriteError,
    ConnectionFailure,
    DuplicateKeyError,
    NetworkTimeout,
    OperationFailure,
    PyMongoError,
    ServerSelectionTimeoutError,
)
import amostras_html as A
from app.routes import transporte_route as R
from app.schemas.transporte_schema import RespostaProcessamentoEPersistenciaSchema, RespostaProcessamentoSchema

URL_PROCESSAR = "/api/transporte/processar-html"
URL_SALVAR = "/api/transporte/processar-e-salvar"
MSG_EXTENSAO = "Envie um arquivo .html ou .htm."
MSG_VAZIO = "O arquivo enviado está vazio."

def enviar(client, url, nome, conteudo, tipo="text/html"):
    return client.post(url, files={"file": (nome, conteudo, tipo)})

def _validar(modelo, dados):
    return (getattr(modelo, "model_validate", None) or modelo.parse_obj)(dados)

class LeitorRegistrador(io.BytesIO):
    #BytesIO que lembra quantos bytes foram lidos (consultável mesmo depois de fechado).

    lido = 0

    def read(self, *args, **kwargs):
        dados = super().read(*args, **kwargs)
        self.lido += len(dados)
        return dados

class UploadFalso:
    #Imita o UploadFile o suficiente para testar _ler_upload_html diretamente.

    def __init__(self, dados=b"conteudo", filename="a.html", size=None):
        self.file, self.filename, self.size = LeitorRegistrador(dados), filename, size

#constantes
def teste_limites_configurados():
    assert R.MAX_UPLOAD_BYTES == 20 * 1024 * 1024
    assert R.CHUNK_SIZE == 1024 * 1024
    assert R.router.prefix == "/transporte"

#POST /processar-html: sucesso
@pytest.mark.parametrize("chave", sorted(A.AMOSTRAS))
def teste_processar_html_sucesso_para_cada_relatorio(client, chave):
    amostra = A.AMOSTRAS[chave]
    resposta = enviar(client, URL_PROCESSAR, amostra.arquivo, amostra.conteudo)
    assert resposta.status_code == 200
    assert resposta.headers["content-type"].startswith("application/json")
    corpo = resposta.json()
    _validar(RespostaProcessamentoSchema, corpo)                       # cumpre o schema declarado
    assert corpo["arquivo"] == amostra.arquivo
    assert corpo["metadados"]["tipo_relatorio"] == amostra.tipo
    assert corpo["total_registros_validos"] == amostra.registros == len(corpo["dados"])
    assert "persistencia" not in corpo

def teste_processar_html_corpo_completo_de_linhas(client, html_linhas):
    corpo = enviar(client, URL_PROCESSAR, "Mensal_Linhas_202608.html", html_linhas).json()
    assert corpo["metadados"] == {"tipo_relatorio": "mensal_linhas", "periodicidade": "mensal", "ano": 2026, "mes": 8,
                                  "semana": None, "data": None, "data_inicio": "2026-08-01", "data_fim": "2026-08-02"}
    assert corpo["dados"][0]["km_total"] == 1062.6 and corpo["dados"][0]["linha"] == "01"
    assert corpo["colunas"][:4] == ["data", "linha", "km_total", "viagens"]

def teste_processar_html_saldos_devolve_os_conjuntos(client, html_saldos):
    corpo = enviar(client, URL_PROCESSAR, "Saldos_Mensal.html", html_saldos).json()
    assert [c["nome"] for c in corpo["conjuntos_dados"]] == ["saldos_creditos", "saldos_movimentacoes"]
    assert corpo["total_registros_conjuntos"] == 4

def teste_processar_html_nao_grava_nada_no_banco(client, conexao_mock, html_linhas):
    assert enviar(client, URL_PROCESSAR, "Mensal_Linhas_202608.html", html_linhas).status_code == 200
    assert conexao_mock.list_collection_names() == []

@pytest.mark.parametrize("nome", ["relatorio.HTML", "relatorio.HTM", "relatorio.htm", "Mensal_Linhas_202608.Html",
                                  "pasta/Mensal_Linhas_202608.html", "relatorio.html "])   # espaços finais são removidos
def teste_extensoes_html_aceitas_sem_diferenciar_maiusculas(client, html_linhas, nome):
    assert enviar(client, URL_PROCESSAR, nome, html_linhas).status_code == 200

@pytest.mark.parametrize("conteudo", [A.HTML_UTF8, A.HTML_LATIN1, A.HTML_CP1252_DECLARADO_UTF8, A.HTML_BYTE_INDEFINIDO_CP1252],
                         ids=["utf8", "latin1", "cp1252-declarado-utf8", "byte-indefinido"])
def teste_encodings_diversos_chegam_ao_cliente_sem_erro(client, conteudo):
    resposta = enviar(client, URL_PROCESSAR, "Mensal_Viag_NRealiz_202608.html", conteudo)
    assert resposta.status_code == 200
    assert "ESTAÇÃO" in resposta.json()["dados"][0]["atendimento"]

#POST /processar-html: 400 (nome, extensão, vazio)
@pytest.mark.parametrize("nome", ["dados.txt", "dados.csv", "dados.xlsx", "dados.pdf", "dados.xml", "dados", "html",
                                  "dados.html.txt", "dados.xhtml", ".htmx"])
def teste_extensao_invalida_retorna_400(client, html_linhas, nome):
    resposta = enviar(client, URL_PROCESSAR, nome, html_linhas)
    assert resposta.status_code == 400
    assert resposta.json() == {"detail": MSG_EXTENSAO}

def teste_arquivo_invalido_do_teste_original_continua_retornando_400(client):
    assert enviar(client, URL_PROCESSAR, "invalido.txt", b"teste", "text/plain").status_code == 400

def teste_nome_vazio_no_multipart_e_rejeitado(client):
    #Starlette recente trata filename="" como campo comum e o FastAPI responde 422;
    #versões anteriores entregam o UploadFile e a rota responde 400. Ambos recusam o envio.
    resposta = enviar(client, URL_PROCESSAR, "", b"<html></html>")
    assert resposta.status_code in (400, 422)

@pytest.mark.parametrize("nome", [None, "", "   "])
def teste_ler_upload_sem_nome_levanta_400_e_fecha_o_arquivo(nome):
    arquivo = UploadFalso(filename=nome)
    with pytest.raises(HTTPException) as erro:
        R._ler_upload_html(arquivo)
    assert erro.value.status_code == 400
    assert erro.value.detail in ("Nome de arquivo não informado.", MSG_EXTENSAO)
    assert arquivo.file.closed

@pytest.mark.parametrize("conteudo", [b""])
def teste_arquivo_vazio_retorna_400(client, conteudo):
    resposta = enviar(client, URL_PROCESSAR, "vazio.html", conteudo)
    assert resposta.status_code == 400
    assert resposta.json() == {"detail": MSG_VAZIO}

def teste_ler_upload_vazio_levanta_400_e_fecha_o_arquivo():
    arquivo = UploadFalso(dados=b"")
    with pytest.raises(HTTPException) as erro:
        R._ler_upload_html(arquivo)
    assert (erro.value.status_code, erro.value.detail) == (400, MSG_VAZIO)
    assert arquivo.file.closed

def teste_ler_upload_valido_devolve_bytes_e_nome_sem_espacos_e_fecha_o_arquivo():
    arquivo = UploadFalso(dados=b"abc", filename="  a.html  ")
    assert R._ler_upload_html(arquivo) == (b"abc", "a.html")
    assert arquivo.file.closed

#POST /processar-html: 413
def teste_arquivo_acima_do_limite_real_retorna_413(client):
    corpo = b"a" * (R.MAX_UPLOAD_BYTES + 1)
    resposta = enviar(client, URL_PROCESSAR, "grande.html", corpo)
    assert resposta.status_code == 413
    assert "20 MB" in resposta.json()["detail"]

def teste_limite_e_inclusivo_no_tamanho_exato_e_exclusivo_acima(client, monkeypatch, html_linhas):
    monkeypatch.setattr(R, "MAX_UPLOAD_BYTES", len(html_linhas))
    assert enviar(client, URL_PROCESSAR, "a.html", html_linhas).status_code == 200
    monkeypatch.setattr(R, "MAX_UPLOAD_BYTES", len(html_linhas) - 1)
    assert enviar(client, URL_PROCESSAR, "a.html", html_linhas).status_code == 413

def teste_413_pela_leitura_em_blocos_quando_o_tamanho_nao_e_informado(monkeypatch):
    monkeypatch.setattr(R, "MAX_UPLOAD_BYTES", 50)
    monkeypatch.setattr(R, "CHUNK_SIZE", 16)
    arquivo = UploadFalso(dados=b"x" * 100, size=None)
    with pytest.raises(HTTPException) as erro:
        R._ler_upload_html(arquivo)
    assert erro.value.status_code == 413
    assert arquivo.file.lido <= 64 and arquivo.file.closed          # parou cedo: não leu o arquivo inteiro

def teste_413_pelo_tamanho_declarado_nem_chega_a_ler_o_conteudo(monkeypatch):
    monkeypatch.setattr(R, "MAX_UPLOAD_BYTES", 50)
    arquivo = UploadFalso(dados=b"x" * 10, size=10 ** 9)
    with pytest.raises(HTTPException) as erro:
        R._ler_upload_html(arquivo)
    assert erro.value.status_code == 413
    assert arquivo.file.lido == 0 and arquivo.file.closed

def teste_leitura_em_varios_blocos_monta_o_conteudo_completo(client, monkeypatch, html_linhas):
    monkeypatch.setattr(R, "CHUNK_SIZE", 7)
    resposta = enviar(client, URL_PROCESSAR, "Mensal_Linhas_202608.html", html_linhas)
    assert resposta.status_code == 200 and resposta.json()["total_registros_validos"] == 4

@pytest.mark.parametrize("tamanho_declarado", [None, 5])
def teste_ler_upload_dentro_do_limite_funciona_com_ou_sem_size(tamanho_declarado):
    assert R._ler_upload_html(UploadFalso(dados=b"abc", size=tamanho_declarado))[0] == b"abc"

#POST /processar-html: 422
@pytest.mark.parametrize("conteudo", [
    A.HTML_SEM_TABELAS, A.HTML_SO_TABELA_INFO, A.HTML_SO_RODAPE, A.HTML_SEM_FECHAMENTO,
    A.HTML_CLASSE_EM_ATRIBUTO_DATA, b"\x00\x01\xff lixo binario",
], ids=["sem-tabelas", "so-info", "so-rodape", "sem-fechamento", "data-class", "binario"])
def teste_html_sem_dados_operacionais_retorna_422_sem_vazar_traceback(client, conteudo):
    resposta = enviar(client, URL_PROCESSAR, "Mensal_Linhas_202608.html", conteudo)
    assert resposta.status_code == 422
    detalhe = resposta.json()["detail"]
    assert detalhe == "Nenhuma tabela operacional encontrada no HTML."
    assert "Traceback" not in resposta.text

def teste_falha_de_parsing_de_todas_as_codificacoes_retorna_422(client, monkeypatch, html_linhas):
    def falhar(*args, **kwargs):
        raise ValueError("falhou de propósito")

    monkeypatch.setattr("app.services.transporte_tables._parsear_tabela", falhar)
    resposta = enviar(client, URL_PROCESSAR, "Mensal_Linhas_202608.html", html_linhas)
    assert resposta.status_code == 422
    assert resposta.json()["detail"].startswith("Não foi possível interpretar")

#validação do FastAPI e roteamento
def teste_requisicao_sem_o_campo_file_retorna_422(client):
    assert client.post(URL_PROCESSAR).status_code == 422
    assert client.post(URL_SALVAR).status_code == 422

def teste_campo_com_nome_diferente_de_file_retorna_422(client, html_linhas):
    resposta = client.post(URL_PROCESSAR, files={"arquivo": ("a.html", html_linhas, "text/html")})
    assert resposta.status_code == 422

@pytest.mark.parametrize("metodo", ["get", "put", "delete", "patch"])
@pytest.mark.parametrize("url", [URL_PROCESSAR, URL_SALVAR])
def teste_somente_post_e_permitido(client, metodo, url):
    assert getattr(client, metodo)(url).status_code == 405

@pytest.mark.parametrize("url", ["/transporte/processar-html", "/api/transporte/inexistente", "/api"])
def teste_rotas_inexistentes_retornam_404(client, url):
    assert client.post(url).status_code in (404, 405)

def teste_openapi_expoe_as_duas_rotas_post_com_os_schemas_de_resposta(client):
    spec = client.get("/openapi.json").json()
    for url, schema in ((URL_PROCESSAR, "RespostaProcessamentoSchema"),
                        (URL_SALVAR, "RespostaProcessamentoEPersistenciaSchema")):
        assert list(spec["paths"][url]) == ["post"]
        resposta_ok = spec["paths"][url]["post"]["responses"]["200"]["content"]["application/json"]["schema"]
        assert resposta_ok["$ref"].endswith(schema)
        assert "Transporte" in spec["paths"][url]["post"]["tags"]

#POST /processar-e-salvar: sucesso
@pytest.mark.parametrize("chave", sorted(A.AMOSTRAS))
def teste_salvar_sucesso_para_cada_relatorio(client, conexao_mock, chave):
    amostra = A.AMOSTRAS[chave]
    resposta = enviar(client, URL_SALVAR, amostra.arquivo, amostra.conteudo)
    assert resposta.status_code == 200
    corpo = resposta.json()
    _validar(RespostaProcessamentoEPersistenciaSchema, corpo)
    assert corpo["persistencia"] == {"colecao": amostra.colecao, "documentos_afetados": amostra.afetados,
                                     "registros_descartados": None if chave == "saldos" else 0}
    assert corpo["total_registros_validos"] == amostra.registros
    assert conexao_mock[amostra.colecao].count_documents({}) == amostra.afetados

@pytest.mark.parametrize("chave", sorted(A.AMOSTRAS))
def teste_salvar_o_mesmo_arquivo_duas_vezes_e_idempotente(client, conexao_mock, chave):
    amostra = A.AMOSTRAS[chave]
    enviar(client, URL_SALVAR, amostra.arquivo, amostra.conteudo)
    segunda = enviar(client, URL_SALVAR, amostra.arquivo, amostra.conteudo).json()
    assert segunda["persistencia"]["documentos_afetados"] == 0
    assert conexao_mock[amostra.colecao].count_documents({}) == amostra.afetados

def teste_salvar_resumo_e_fcv_via_api_consolida_documentos(client, conexao_mock, html_resumo, html_fcv):
    enviar(client, URL_SALVAR, "Mensal_202608.html", html_resumo)
    enviar(client, URL_SALVAR, "Mensal_FCV_202608.html", html_fcv)
    docs = list(conexao_mock["viagensSistema"].find({}, {"_id": 0}))
    assert len(docs) == 3 and all("kmTotal" in d and "fcvPorPeriodo" in d for d in docs)

def teste_salvar_registros_descartados_sao_informados(client, conexao_mock):
    html = A.montar_html([A.tabela(A.CAB_LINHAS, [["01/08/2026", "01", "1,5", "3"], ["01/08/2026", "", "2,5", "4"]])])
    corpo = enviar(client, URL_SALVAR, "Mensal_Linhas_202608.html", html).json()
    assert corpo["persistencia"]["registros_descartados"] == 1 and corpo["persistencia"]["documentos_afetados"] == 1

#POST /processar-e-salvar: erros do cliente
@pytest.mark.parametrize("nome, conteudo, status", [
    ("dados.txt", b"abc", 400),
    ("vazio.html", b"", 400),
    ("Mensal_Linhas_202608.html", A.HTML_SEM_TABELAS, 422),
    ("Relatorio_Desconhecido.html", A.AMOSTRAS["linhas"].conteudo, 422),
    ("Mensal_Resumo_FxHr_202608.html", A.AMOSTRAS_SEM_COLECAO["resumo_fxhr"].conteudo, 422),
    ("Mensal_Viagens_202608.html", A.AMOSTRAS_SEM_COLECAO["viagens"].conteudo, 422),
])
def teste_salvar_erros_do_cliente_nao_gravam_nada(client, conexao_mock, nome, conteudo, status):
    resposta = enviar(client, URL_SALVAR, nome, conteudo)
    assert resposta.status_code == status
    assert "detail" in resposta.json()
    assert conexao_mock.list_collection_names() == []

def teste_salvar_tipo_sem_colecao_explica_o_motivo(client, conexao_mock):
    amostra = A.AMOSTRAS_SEM_COLECAO["viagens"]
    detalhe = enviar(client, URL_SALVAR, amostra.arquivo, amostra.conteudo).json()["detail"]
    assert "sem coleção de destino definida" in detalhe and "/processar-html" in detalhe

def teste_salvar_arquivo_acima_do_limite_retorna_413_sem_tocar_no_banco(client, conexao_mock, monkeypatch, html_linhas):
    monkeypatch.setattr(R, "MAX_UPLOAD_BYTES", 10)
    assert enviar(client, URL_SALVAR, "Mensal_Linhas_202608.html", html_linhas).status_code == 413
    assert conexao_mock.list_collection_names() == []

#POST /processar-e-salvar: infraestrutura (503) e 500
SEGREDO = "mongodb://admin:senha-super-secreta@cluster.interno:27017"

def _falhar_com(excecao):
    def _funcao(*args, **kwargs):
        raise excecao

    return _funcao

@pytest.mark.parametrize("excecao", [
    PyMongoError(f"falha em {SEGREDO}"),
    ServerSelectionTimeoutError(f"{SEGREDO}: timed out"),
    AutoReconnect(SEGREDO),
    ConnectionFailure(SEGREDO),
    NetworkTimeout(SEGREDO),
    OperationFailure(f"not authorized {SEGREDO}", 13),
    DuplicateKeyError(f"E11000 {SEGREDO}", 11000),
    BulkWriteError({"writeErrors": [{"errmsg": SEGREDO}], "nInserted": 0}),
], ids=lambda e: type(e).__name__)
def teste_erros_do_pymongo_retornam_503_sem_vazar_detalhes(client, monkeypatch, html_linhas, excecao):
    monkeypatch.setattr(R, "processar_e_persistir_html_bytes", _falhar_com(excecao))
    resposta = enviar(client, URL_SALVAR, "Mensal_Linhas_202608.html", html_linhas)
    assert resposta.status_code == 503
    assert resposta.json() == {"detail": "Falha ao acessar o banco de dados."}
    assert "senha-super-secreta" not in resposta.text and "cluster.interno" not in resposta.text

def teste_runtimeerror_de_configuracao_retorna_503_sem_vazar_detalhes(client, monkeypatch, html_linhas):
    monkeypatch.setattr(R, "processar_e_persistir_html_bytes", _falhar_com(RuntimeError(f"config {SEGREDO}")))
    resposta = enviar(client, URL_SALVAR, "Mensal_Linhas_202608.html", html_linhas)
    assert resposta.status_code == 503
    assert resposta.json() == {"detail": "Banco de dados não configurado."}
    assert "senha-super-secreta" not in resposta.text

def teste_sem_variaveis_de_ambiente_a_api_responde_503_de_ponta_a_ponta(client, factory_limpa, sem_env_mongo, html_linhas):
    resposta = enviar(client, URL_SALVAR, "Mensal_Linhas_202608.html", html_linhas)
    assert resposta.status_code == 503
    assert resposta.json() == {"detail": "Banco de dados não configurado."}

def teste_falha_de_escrita_no_banco_real_do_pymongo_retorna_503(client, conexao_mock, monkeypatch, html_linhas):
    def bulk_write_falho(self, *args, **kwargs):
        raise AutoReconnect(SEGREDO)

    monkeypatch.setattr(type(conexao_mock["viagensLinhas"]), "bulk_write", bulk_write_falho)
    resposta = enviar(client, URL_SALVAR, "Mensal_Linhas_202608.html", html_linhas)
    assert resposta.status_code == 503 and "senha-super-secreta" not in resposta.text

@pytest.mark.parametrize("excecao, mensagem", [
    (PyMongoError("falha"), "Falha ao persistir no MongoDB"),
    (RuntimeError("cfg"), "Erro de configuração do banco"),
])
def teste_falhas_de_infraestrutura_sao_registradas_no_log_com_traceback(client, monkeypatch, html_linhas, caplog,
                                                                        excecao, mensagem):
    monkeypatch.setattr(R, "processar_e_persistir_html_bytes", _falhar_com(excecao))
    with caplog.at_level(logging.ERROR, logger=R.logger.name):
        enviar(client, URL_SALVAR, "Mensal_Linhas_202608.html", html_linhas)
    assert mensagem in caplog.text
    assert any(registro.exc_info for registro in caplog.records)

@pytest.mark.parametrize("excecao", [KeyError("chave-secreta"), TypeError("detalhe-interno"), ZeroDivisionError("x")],
                         ids=lambda e: type(e).__name__)
def teste_erro_inesperado_vira_500_generico_sem_vazar_a_mensagem(client, monkeypatch, html_linhas, excecao):
    monkeypatch.setattr(R, "processar_e_persistir_html_bytes", _falhar_com(excecao))
    resposta = enviar(client, URL_SALVAR, "Mensal_Linhas_202608.html", html_linhas)
    assert resposta.status_code == 500
    assert "chave-secreta" not in resposta.text and "detalhe-interno" not in resposta.text

def teste_valueerror_do_servico_de_persistencia_retorna_422(client, monkeypatch, html_linhas):
    monkeypatch.setattr(R, "processar_e_persistir_html_bytes", _falhar_com(ValueError("tipo inválido")))
    resposta = enviar(client, URL_SALVAR, "Mensal_Linhas_202608.html", html_linhas)
    assert (resposta.status_code, resposta.json()) == (422, {"detail": "tipo inválido"})

def teste_erro_inesperado_em_processar_html_tambem_vira_500(client, monkeypatch, html_linhas):
    monkeypatch.setattr(R, "processar_html_bytes", _falhar_com(KeyError("interno")))
    resposta = enviar(client, URL_PROCESSAR, "Mensal_Linhas_202608.html", html_linhas)
    assert resposta.status_code == 500 and "interno" not in resposta.text