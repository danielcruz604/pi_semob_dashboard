import threading
from datetime import datetime
import pytest
from pymongo.errors import DuplicateKeyError
from app.services import transporte_repository as R
from app.services.transporte_repository import (
    CHAVES_UNICAS,
    COL_FINANCEIRO_SISTEMA,
    COL_PASSAGEIROS_SISTEMA,
    COL_VIAGENS_HORARIO,
    COL_VIAGENS_LINHAS,
    COL_VIAGENS_OCORRENCIAS,
    COL_VIAGENS_SISTEMA,
    _achatar,
    garantir_indices,
)

D1 = datetime(2026, 8, 1)
D2 = datetime(2026, 8, 2)

#_achatar
@pytest.mark.parametrize("documento, esperado", [
    ({"a": 1, "b": "x"}, {"a": 1, "b": "x"}),
    ({"a": {"b": 1}}, {"a.b": 1}),
    ({"a": {"b": {"c": 1, "d": 2}}, "e": 3}, {"a.b.c": 1, "a.b.d": 2, "e": 3}),
    ({"a": None, "b": 1}, {"b": 1}),                                    # None é descartado
    ({"a": {"b": None, "c": 2}}, {"a.c": 2}),                           # inclusive em nível interno
    ({"zero": 0, "falso": False, "vazio": "", "lista": []}, {"zero": 0, "falso": False, "vazio": "", "lista": []}),
    ({"partidas": [34, 57]}, {"partidas": [34, 57]}),                   # listas não são achatadas
    ({"data": D1}, {"data": D1}),
    ({"a": {}}, {}),                                                     # dict vazio não gera campo
    ({}, {}),
])
def teste_achatar(documento, esperado):
    assert _achatar(documento) == esperado

def teste_achatar_nao_altera_o_documento_original():
    documento = {"a": {"b": None, "c": 1}}
    _achatar(documento)
    assert documento == {"a": {"b": None, "c": 1}}

def teste_achatar_com_prefixo():
    assert _achatar({"x": 1, "y": {"z": 2}}, "pai.") == {"pai.x": 1, "pai.y.z": 2}

#garantir_indices
def teste_chaves_unicas_cobrem_todas_as_colecoes():
    assert set(CHAVES_UNICAS) == {COL_VIAGENS_SISTEMA, COL_VIAGENS_LINHAS, COL_VIAGENS_HORARIO,
                                  COL_VIAGENS_OCORRENCIAS, COL_PASSAGEIROS_SISTEMA, COL_FINANCEIRO_SISTEMA}

@pytest.mark.parametrize("colecao, campos", sorted(CHAVES_UNICAS.items()))
def teste_garantir_indices_cria_indice_unico_por_colecao(db, colecao, campos):
    garantir_indices(db)
    indices = db[colecao].index_information()
    nome = "uq_" + "_".join(campos)
    assert nome in indices
    assert indices[nome]["unique"] is True
    assert list(indices[nome]["key"]) == [(campo, 1) for campo in campos]

def teste_garantir_indices_e_idempotente(db):
    garantir_indices(db)
    garantir_indices(db)
    assert sum(1 for nome in db[COL_VIAGENS_SISTEMA].index_information() if nome.startswith("uq_")) == 1

@pytest.mark.parametrize("colecao, doc", [
    (COL_VIAGENS_SISTEMA, {"data": D1}),
    (COL_VIAGENS_LINHAS, {"data": D1, "linha": "01"}),
    (COL_VIAGENS_HORARIO, {"data": D1, "linha": "01", "hora": 4}),
    (COL_VIAGENS_OCORRENCIAS, {"data": D1, "linha": "01", "prefixo": 1, "inicioProgramado": D1, "classificacao": "X"}),
    (COL_PASSAGEIROS_SISTEMA, {"data": D1}),
    (COL_FINANCEIRO_SISTEMA, {"data": D1}),
])
def teste_indice_unico_impede_duplicatas_na_chave(db_com_indices, colecao, doc):
    db_com_indices[colecao].insert_one(dict(doc))
    with pytest.raises(DuplicateKeyError):
        db_com_indices[colecao].insert_one(dict(doc))

#upserts: idempotência e atualização parcial
DOCUMENTOS = [
    (R.upsert_viagens_sistema, COL_VIAGENS_SISTEMA, {"data": D1, "kmTotal": 10.0, "nrViagensProg": 5}),
    (R.upsert_viagens_linhas, COL_VIAGENS_LINHAS, {"data": D1, "linha": "01", "kmTotal": 10.0, "nrViagens": 5}),
    (R.upsert_viagens_horario, COL_VIAGENS_HORARIO,
     {"data": D1, "linha": "01", "hora": 4, "nrViagens": 3, "partidas": [34, 57, 59]}),
    (R.upsert_viagens_ocorrencias, COL_VIAGENS_OCORRENCIAS,
     {"data": D1, "linha": "01", "prefixo": 7, "inicioProgramado": D1, "classificacao": "NaoRealizada", "kmProd": 1.5}),
    (R.upsert_passageiros_sistema, COL_PASSAGEIROS_SISTEMA, {"data": D1, "catraca": 100, "totalPassageiros": 150}),
    (R.upsert_financeiro_sistema, COL_FINANCEIRO_SISTEMA, {"data": D1, "saldoFinal": 1.5, "totalVendas": 2.5}),
]
IDS = [c for _, c, _ in DOCUMENTOS]

@pytest.mark.parametrize("funcao, colecao, doc", DOCUMENTOS, ids=IDS)
def teste_upsert_insere_e_retorna_a_quantidade(db, funcao, colecao, doc):
    assert funcao(db, [dict(doc)]) == 1
    gravado = db[colecao].find_one({}, {"_id": 0})
    for chave, valor in doc.items():
        assert gravado[chave] == valor

@pytest.mark.parametrize("funcao, colecao, doc", DOCUMENTOS, ids=IDS)
def teste_reprocessar_o_mesmo_relatorio_nao_duplica_nem_conta_como_alterado(db, funcao, colecao, doc):
    funcao(db, [dict(doc)])
    assert funcao(db, [dict(doc)]) == 0
    assert db[colecao].count_documents({}) == 1

@pytest.mark.parametrize("funcao, colecao, doc", DOCUMENTOS, ids=IDS)
def teste_reprocessar_com_valor_novo_atualiza_o_mesmo_documento(db, funcao, colecao, doc):
    funcao(db, [dict(doc)])
    campo_numerico = next(k for k, v in doc.items() if isinstance(v, (int, float)) and k not in CHAVES_UNICAS[colecao])
    alterado = {**doc, campo_numerico: doc[campo_numerico] + 1}
    assert funcao(db, [alterado]) == 1
    assert db[colecao].count_documents({}) == 1
    assert db[colecao].find_one({}, {"_id": 0})[campo_numerico] == doc[campo_numerico] + 1

@pytest.mark.parametrize("funcao, colecao, doc", DOCUMENTOS, ids=IDS)
def teste_lista_vazia_retorna_zero_e_nao_toca_no_banco(db, funcao, colecao, doc):
    assert funcao(db, []) == 0
    assert colecao not in db.list_collection_names()

@pytest.mark.parametrize("funcao, colecao, doc", DOCUMENTOS, ids=IDS)
def teste_documentos_em_lote_sao_gravados_juntos(db, funcao, colecao, doc):
    chave_variavel = {COL_VIAGENS_LINHAS: "linha", COL_VIAGENS_HORARIO: "hora",
                      COL_VIAGENS_OCORRENCIAS: "inicioProgramado"}.get(colecao, "data")
    valores = {"data": [D1, D2, datetime(2026, 8, 3)], "linha": ["01", "02", "03"], "hora": [4, 5, 6],
               "inicioProgramado": [D1, D2, datetime(2026, 8, 3)]}[chave_variavel]
    lote = [{**doc, chave_variavel: v} for v in valores]
    assert funcao(db, lote) == 3
    assert db[colecao].count_documents({}) == 3

def teste_atualizacao_parcial_preserva_campos_nao_enviados(db):
    R.upsert_viagens_sistema(db, [{"data": D1, "nrVeiculos": 37, "kmTotal": 10.0}])
    R.upsert_viagens_sistema(db, [{"data": D1, "nrViagensProg": 924}])
    assert db[COL_VIAGENS_SISTEMA].find_one({}, {"_id": 0}) == {
        "data": D1, "nrVeiculos": 37, "kmTotal": 10.0, "nrViagensProg": 924}

def teste_valor_none_nao_apaga_campo_existente(db):
    R.upsert_viagens_sistema(db, [{"data": D1, "kmTotal": 10.0}])
    R.upsert_viagens_sistema(db, [{"data": D1, "kmTotal": None, "nrVeiculos": 3}])
    gravado = db[COL_VIAGENS_SISTEMA].find_one({}, {"_id": 0})
    assert gravado["kmTotal"] == 10.0 and gravado["nrVeiculos"] == 3

def teste_valores_zero_sao_gravados_e_sobrescrevem(db):
    R.upsert_viagens_sistema(db, [{"data": D1, "kmTotal": 10.0}])
    R.upsert_viagens_sistema(db, [{"data": D1, "kmTotal": 0.0}])
    assert db[COL_VIAGENS_SISTEMA].find_one({}, {"_id": 0})["kmTotal"] == 0.0

def teste_fcv_por_periodo_e_mesclado_por_periodo_sem_apagar_os_demais(db):
    manha_tarde_noite = {"manha": {"prog": 1, "real": 1, "fcv": 1.0}, "tarde": {"prog": 2, "real": 2, "fcv": 1.0},
                         "noite": {"prog": 3, "real": 3, "fcv": 1.0}}
    R.upsert_viagens_sistema(db, [{"data": D1, "fcvPorPeriodo": manha_tarde_noite}])
    R.upsert_viagens_sistema(db, [{"data": D1, "fcvPorPeriodo": {"manha": {"prog": 10, "real": 5, "fcv": 0.5}}}])
    gravado = db[COL_VIAGENS_SISTEMA].find_one({}, {"_id": 0})["fcvPorPeriodo"]
    assert gravado["manha"] == {"prog": 10, "real": 5, "fcv": 0.5}
    assert gravado["tarde"]["prog"] == 2 and gravado["noite"]["prog"] == 3

def teste_chave_composta_diferencia_documentos(db):
    R.upsert_viagens_linhas(db, [{"data": D1, "linha": "01", "nrViagens": 1}, {"data": D1, "linha": "02", "nrViagens": 2},
                                 {"data": D2, "linha": "01", "nrViagens": 3}])
    assert db[COL_VIAGENS_LINHAS].count_documents({}) == 3

def teste_ocorrencias_com_classificacoes_diferentes_sao_documentos_distintos(db):
    base = {"data": D1, "linha": "01", "prefixo": 7, "inicioProgramado": D1}
    R.upsert_viagens_ocorrencias(db, [{**base, "classificacao": "NaoIniciada"}, {**base, "classificacao": "NaoTerminada"}])
    assert db[COL_VIAGENS_OCORRENCIAS].count_documents({}) == 2

def teste_ocorrencias_sem_prefixo_idempotentes(db):
    doc = {"data": D1, "linha": "01", "prefixo": None, "inicioProgramado": D1, "classificacao": "NaoRealizada"}
    R.upsert_viagens_ocorrencias(db, [dict(doc)])
    assert R.upsert_viagens_ocorrencias(db, [dict(doc)]) == 0
    assert db[COL_VIAGENS_OCORRENCIAS].count_documents({}) == 1

def teste_documento_repetido_no_mesmo_lote_nao_duplica(db_com_indices):
    R.upsert_viagens_sistema(db_com_indices, [{"data": D1, "kmTotal": 1.0}, {"data": D1, "kmTotal": 2.0}])
    assert db_com_indices[COL_VIAGENS_SISTEMA].count_documents({}) == 1

def teste_upserts_continuam_idempotentes_com_indices_unicos_ativos(db_com_indices):
    R.upsert_viagens_horario(db_com_indices, [{"data": D1, "linha": "01", "hora": 4, "nrViagens": 3}])
    assert R.upsert_viagens_horario(db_com_indices, [{"data": D1, "linha": "01", "hora": 4, "nrViagens": 3}]) == 0
    assert db_com_indices[COL_VIAGENS_HORARIO].count_documents({}) == 1

#ConnectionFactory
class ClienteFalso:
    #Substitui pymongo.MongoClient: registra argumentos e evita qualquer conexão de rede.

    criados = []

    def __init__(self, uri, **opcoes):
        self.uri, self.opcoes, self.fechado = uri, opcoes, False
        ClienteFalso.criados.append(self)

    def __getitem__(self, nome):
        return f"banco:{nome}"

    def close(self):
        self.fechado = True

@pytest.fixture
def cliente_falso(monkeypatch, factory_limpa):
    ClienteFalso.criados = []
    monkeypatch.setattr("app.utils.connection_factory.MongoClient", ClienteFalso)
    return ClienteFalso

@pytest.mark.parametrize("uri, nome", [(None, None), ("mongodb://x", None), (None, "banco"), ("", "banco"), ("mongodb://x", "")])
def teste_variaveis_ausentes_ou_vazias_levantam_runtimeerror_sem_conectar(
        monkeypatch, cliente_falso, uri, nome):
    for variavel, valor in (("MONGO_URI", uri), ("DATABASE_NAME", nome)):
        if valor is None:
            monkeypatch.delenv(variavel, raising=False)
        else:
            monkeypatch.setenv(variavel, valor)
    with pytest.raises(RuntimeError, match="MONGO_URI e DATABASE_NAME"):
        cliente_falso_db = cliente_falso  # noqa: F841 (mantém a fixture ativa)
        from app.utils.connection_factory import ConnectionFactory
        ConnectionFactory().db
    assert cliente_falso.criados == []

def teste_com_variaveis_cria_cliente_com_timeout_e_devolve_o_banco(monkeypatch, cliente_falso):
    monkeypatch.setenv("MONGO_URI", "mongodb://host:27017")
    monkeypatch.setenv("DATABASE_NAME", "meu_banco")
    from app.utils.connection_factory import ConnectionFactory
    assert ConnectionFactory().db == "banco:meu_banco"
    (cliente,) = cliente_falso.criados
    assert cliente.uri == "mongodb://host:27017"
    assert cliente.opcoes == {"serverSelectionTimeoutMS": 5000}

def teste_singleton_e_conexao_unica(com_env_mongo, cliente_falso):
    from app.utils.connection_factory import ConnectionFactory
    assert ConnectionFactory() is ConnectionFactory()
    assert ConnectionFactory().db is ConnectionFactory().db
    assert len(cliente_falso.criados) == 1

def teste_variaveis_sao_lidas_somente_no_primeiro_uso(monkeypatch, cliente_falso):
    from app.utils.connection_factory import ConnectionFactory
    fabrica = ConnectionFactory()                       # instanciar não exige variáveis nem conecta
    assert cliente_falso.criados == []
    monkeypatch.setenv("MONGO_URI", "mongodb://x")
    monkeypatch.setenv("DATABASE_NAME", "b1")
    assert fabrica.db == "banco:b1"
    monkeypatch.setenv("DATABASE_NAME", "b2")
    assert fabrica.db == "banco:b1"                     # já conectado: não relê o ambiente

def teste_close_fecha_o_cliente_e_a_proxima_chamada_reconecta(com_env_mongo, cliente_falso):
    from app.utils.connection_factory import ConnectionFactory
    fabrica = ConnectionFactory()
    fabrica.db
    fabrica.close()
    assert cliente_falso.criados[0].fechado is True
    fabrica.db
    assert len(cliente_falso.criados) == 2

def teste_close_sem_conexao_previa_nao_levanta_erro(factory_limpa):
    factory_limpa().close()

def teste_acesso_concorrente_cria_um_unico_cliente(com_env_mongo, cliente_falso):
    from app.utils.connection_factory import ConnectionFactory
    liberar, resultados = threading.Event(), []

    def acessar():
        liberar.wait()
        resultados.append(ConnectionFactory().db)

    threads = [threading.Thread(target=acessar) for _ in range(16)]
    for t in threads:
        t.start()
    liberar.set()
    for t in threads:
        t.join()
    assert len(cliente_falso.criados) == 1
    assert len(set(map(id, resultados))) == 1 and len(resultados) == 16

def teste_cliente_real_do_pymongo_respeita_o_timeout_sem_conectar(com_env_mongo, factory_limpa):
    from pymongo.database import Database
    banco = factory_limpa().db                           # criação é preguiçosa: nenhuma conexão é aberta
    assert isinstance(banco, Database) and banco.name == "banco_teste"
    assert banco.client.options.server_selection_timeout == 5