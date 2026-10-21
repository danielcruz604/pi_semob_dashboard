import logging
import pytest
from fastapi.testclient import TestClient
from pymongo.errors import PyMongoError, ServerSelectionTimeoutError
import amostras_html as A
import main

URL = "/api/transporte/processar-html"

class FabricaFalsa:
    #Substitui ConnectionFactory em main: registra o uso sem tocar em rede.

    instancias = []

    def __init__(self):
        self.db_acessado, self.fechada = 0, 0
        FabricaFalsa.instancias.append(self)

    @property
    def db(self):
        self.db_acessado += 1
        return "banco-falso"

    def close(self):
        self.fechada += 1

@pytest.fixture
def fabrica_falsa(monkeypatch):
    FabricaFalsa.instancias = []
    monkeypatch.setattr(main, "ConnectionFactory", FabricaFalsa)
    return FabricaFalsa

#montagem do app
def teste_metadados_do_app():
    assert main.app.title == "API de Transporte Municipal"
    assert main.app.version == "1.0.0"

def teste_rotas_ficam_sob_o_prefixo_api(client):
    caminhos = set(client.get("/openapi.json").json()["paths"]) - {"/"}
    rotas_esperadas = {
        "/api/transporte/processar-html",
        "/api/transporte/processar-e-salvar",
        "/api/dashboard/resumo-operacional",
        "/api/dashboard/serie-temporal",
        "/api/dashboard/anomalias",
        "/api/dashboard/relatorio",
        "/api/dashboard/relatorio/upload-e-gerar",
        "/api/v1/relatorios/upload",
        "/api/v1/dashboard/metricas",
    }
    assert rotas_esperadas <= caminhos
    assert all(c.startswith("/api/") for c in caminhos)


def teste_arquivo_invalido_retorna_400(client):
    resposta = client.post(URL, files={"file": ("invalido.txt", b"teste", "text/plain")})
    assert resposta.status_code == 400

def teste_processar_html_responde_200_pela_aplicacao_completa(client, html_saldos):
    resposta = client.post(URL, files={"file": ("Saldos_Mensal.html", html_saldos, "text/html")})
    assert resposta.status_code == 200
    assert resposta.json()["total_registros_validos"] > 0 and len(resposta.json()["dados"]) > 0

@pytest.mark.real_data
def teste_processar_html_real(client, pasta_dados_reais):
    arquivo = next(pasta_dados_reais.rglob("Saldos_Mensal.html"), None)
    if arquivo is None:
        pytest.skip("Saldos_Mensal.html não encontrado em TRANSPORTE_DADOS_DIR")
    resposta = client.post(URL, files={"file": (arquivo.name, arquivo.read_bytes(), "text/html")})
    assert resposta.status_code == 200
    assert resposta.json()["total_registros_validos"] > 0

#lifespan
def teste_startup_cria_indices_e_shutdown_fecha_a_conexao(monkeypatch, fabrica_falsa):
    chamadas = []
    monkeypatch.setattr(main, "garantir_indices", lambda db: chamadas.append(db))
    with TestClient(main.app) as cliente:
        assert chamadas == ["banco-falso"]
        assert all(f.fechada == 0 for f in fabrica_falsa.instancias)
        assert cliente.get("/openapi.json").status_code == 200
    assert any(f.fechada == 1 for f in fabrica_falsa.instancias)

def teste_startup_cria_os_indices_unicos_no_banco_em_memoria(conexao_mock):
    with TestClient(main.app):
        pass
    assert "uq_data" in conexao_mock["viagensSistema"].index_information()
    assert "uq_data_linha_hora" in conexao_mock["viagensHorario"].index_information()

@pytest.mark.parametrize("excecao", [
    PyMongoError("falha"), ServerSelectionTimeoutError("sem servidor"), RuntimeError("variáveis ausentes"),
], ids=lambda e: type(e).__name__)
def teste_falha_ao_criar_indices_nao_derruba_o_app_e_e_registrada(monkeypatch, fabrica_falsa, caplog, excecao):
    def falhar(db):
        raise excecao
    monkeypatch.setattr(main, "garantir_indices", falhar)
    with caplog.at_level(logging.ERROR, logger=main.logger.name):
        with TestClient(main.app) as cliente:
            assert cliente.get("/openapi.json").status_code == 200
    assert "Não foi possível garantir os índices" in caplog.text
    assert any(f.fechada == 1 for f in fabrica_falsa.instancias)

def teste_startup_sem_variaveis_de_ambiente_apenas_registra_o_erro(factory_limpa, sem_env_mongo, caplog):
    with caplog.at_level(logging.ERROR, logger=main.logger.name):
        with TestClient(main.app) as cliente:
            resposta = cliente.post(URL, files={"file": ("Mensal_Linhas_202608.html", A.AMOSTRAS["linhas"].conteudo, "text/html")})
            assert resposta.status_code == 200
    assert "Não foi possível garantir os índices" in caplog.text

def teste_exception_nao_tratada_no_startup_nao_e_engolida(monkeypatch, fabrica_falsa):
    monkeypatch.setattr(main, "garantir_indices", lambda db: (_ for _ in ()).throw(KeyError("bug")))
    with pytest.raises(KeyError):
        with TestClient(main.app):
            pass