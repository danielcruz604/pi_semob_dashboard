#Fixtures globais da suíte de testes.
#Variáveis de ambiente opcionais:
#TRANSPORTE_DADOS_DIR            pasta com os HTMLs reais (ex.: ZIP extraído); habilita os testes de massa real.
#TRANSPORTE_TESTAR_GRANDES=1     inclui os arquivos reais acima de 3 MB (lentos).
import inspect
import os
import sys
from pathlib import Path
import mongomock
import pytest
from fastapi.testclient import TestClient

def _ajustar_sys_path():
    #torna importáveis o main.py (raiz do projeto) e o amostras_html.py (pasta deste arquivo), em qualquer layout
    aqui = Path(__file__).resolve().parent
    raiz = next((p for p in [aqui, *aqui.parents] if (p / "main.py").is_file() and (p / "app").is_dir()), aqui)
    for pasta in (raiz, aqui):
        if str(pasta) not in sys.path:
            sys.path.insert(0, str(pasta))

_ajustar_sys_path()
os.environ.setdefault("MONGO_URI", "mongodb://localhost:27017")
os.environ.setdefault("DATABASE_NAME", "semob_teste")
os.environ.setdefault("JWT_SECRET", "semob_dev_test_secret_key_fallback_32bytes")
import amostras_html as A

def _compatibilizar_mongomock() -> None:
    #mongomock 4.3 não aceita `sort` em add_update, mas pymongo >= 4.12 o envia em UpdateOne.
    #Sem este ajuste, qualquer bulk_write de UpdateOne falha com TypeError no ambiente de teste.
    #É um no-op quando o mongomock instalado já suporta o argumento.
    from mongomock.collection import BulkOperationBuilder

    if "sort" in inspect.signature(BulkOperationBuilder.add_update).parameters:
        return
    original = BulkOperationBuilder.add_update

    def add_update(self, *args, sort=None, **kwargs):
        return original(self, *args, **kwargs)

    BulkOperationBuilder.add_update = add_update

_compatibilizar_mongomock()

#API e banco
@pytest.fixture
def client():
    #TestClient do app real (main.py). Exceções não tratadas viram respostas HTTP 500.
    from main import app

    return TestClient(app, raise_server_exceptions=False)

@pytest.fixture
def db():
    #Banco MongoDB em memória, novo a cada teste (não toca em nenhum ambiente real).
    return mongomock.MongoClient().db

@pytest.fixture
def db_com_indices(db):
    from app.services.transporte_repository import garantir_indices

    garantir_indices(db)
    return db

@pytest.fixture
def conexao_mock(monkeypatch, db):
    #Faz `ConnectionFactory().db` devolver o banco em memória (usado pelas rotas e pelo serviço).
    from app.utils.connection_factory import ConnectionFactory

    monkeypatch.setattr(ConnectionFactory, "db", property(lambda self: db))
    return db

@pytest.fixture
def factory_limpa():
    #Zera o singleton de ConnectionFactory antes e depois do teste.
    from app.utils.connection_factory import ConnectionFactory

    def _zerar():
        instancia = ConnectionFactory._instance
        if instancia is not None:
            instancia.close()
        ConnectionFactory._instance = None

    _zerar()
    yield ConnectionFactory
    _zerar()

@pytest.fixture
def sem_env_mongo(monkeypatch):
    monkeypatch.delenv("MONGO_URI", raising=False)
    monkeypatch.delenv("DATABASE_NAME", raising=False)

@pytest.fixture
def com_env_mongo(monkeypatch):
    monkeypatch.setenv("MONGO_URI", "mongodb://localhost:27017")
    monkeypatch.setenv("DATABASE_NAME", "banco_teste")

#HTMLs em memória
@pytest.fixture
def html_builder():
    #Acesso às funções de montagem: `tabela(...)` e `montar_html([...])`.
    return A

@pytest.fixture
def html_resumo():
    return A.AMOSTRAS["resumo"].conteudo

@pytest.fixture
def html_fcv():
    return A.AMOSTRAS["fcv"].conteudo

@pytest.fixture
def html_linhas():
    return A.AMOSTRAS["linhas"].conteudo

@pytest.fixture
def html_fxhr():
    return A.AMOSTRAS["fxhr"].conteudo

@pytest.fixture
def html_ocorrencias():
    return A.AMOSTRAS["nrealiz"].conteudo

@pytest.fixture
def html_passageiros():
    return A.AMOSTRAS["passageiros"].conteudo

@pytest.fixture
def html_saldos():
    #Duas tabelas (créditos e movimentações) mais o rodapé 'Gerado por Smart Report'.
    return A.AMOSTRAS["saldos"].conteudo

@pytest.fixture
def html_vazio():
    return A.HTML_VAZIO

@pytest.fixture
def html_sem_tabela_data():
    return A.HTML_SO_TABELA_INFO

@pytest.fixture
def html_colunas_desordenadas():
    return A.HTML_COLUNAS_DESORDENADAS

@pytest.fixture
def html_colunas_ausentes():
    return A.HTML_COLUNAS_AUSENTES

@pytest.fixture
def html_encoding_corrompido():
    #Declara utf-8, mas os bytes são cp1252 (ex.: 0xC7 isolado, inválido em utf-8).
    return A.HTML_CP1252_DECLARADO_UTF8

@pytest.fixture
def html_apenas_totais():
    return A.HTML_APENAS_TOTAIS

#massa real (opcional)
@pytest.fixture(scope="session")
def pasta_dados_reais() -> Path:
    pasta = os.getenv("TRANSPORTE_DADOS_DIR")
    if not pasta or not Path(pasta).is_dir():
        pytest.skip("Defina TRANSPORTE_DADOS_DIR com a pasta dos HTMLs reais para rodar estes testes.")
    return Path(pasta)