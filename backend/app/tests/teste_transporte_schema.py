import pytest
from pydantic import ValidationError
import amostras_html as A
from app.schemas.transporte_schema import (
    ConjuntoDadosSchema,
    MetadadosSchema,
    PersistenciaSchema,
    RespostaProcessamentoEPersistenciaSchema,
    RespostaProcessamentoSchema,
)
from app.services.transporte_service import processar_e_persistir_html_bytes, processar_html_bytes

def _validar(modelo, dados):
    #Compatível com pydantic v2 (model_validate) e v1 (parse_obj).
    return (getattr(modelo, "model_validate", None) or modelo.parse_obj)(dados)

def _dump(instancia):
    return (getattr(instancia, "model_dump", None) or instancia.dict)()

METADADOS = {"tipo_relatorio": "mensal_linhas"}
RESPOSTA = {"arquivo": "a.html", "metadados": METADADOS, "total_registros_validos": 0, "colunas": [], "dados": []}

#MetadadosSchema
def teste_metadados_somente_tipo_e_obrigatorio_e_o_resto_e_none():
    m = _validar(MetadadosSchema, METADADOS)
    assert m.tipo_relatorio == "mensal_linhas"
    assert all(getattr(m, c) is None for c in ("periodicidade", "ano", "mes", "semana", "data", "data_inicio", "data_fim"))

def teste_metadados_sem_tipo_e_invalido():
    with pytest.raises(ValidationError):
        _validar(MetadadosSchema, {"ano": 2026})

@pytest.mark.parametrize("campo, valor", [("ano", "abc"), ("mes", "x"), ("semana", [1])])
def teste_metadados_tipos_numericos_invalidos_sao_rejeitados(campo, valor):
    with pytest.raises(ValidationError):
        _validar(MetadadosSchema, {**METADADOS, campo: valor})

#ConjuntoDadosSchema / Persistencia
def teste_conjunto_dados_campos_obrigatorios():
    c = _validar(ConjuntoDadosSchema, {"nome": "x", "colunas": ["a"], "total_registros_validos": 1, "dados": [{"a": 1}]})
    assert c.dados == [{"a": 1}]
    with pytest.raises(ValidationError):
        _validar(ConjuntoDadosSchema, {"nome": "x"})

def teste_persistencia_descartados_e_opcional_e_afetados_obrigatorio():
    assert _validar(PersistenciaSchema, {"colecao": "c", "documentos_afetados": 3}).registros_descartados is None
    assert _validar(PersistenciaSchema, {"colecao": "c", "documentos_afetados": 3, "registros_descartados": 1}).registros_descartados == 1
    with pytest.raises(ValidationError):
        _validar(PersistenciaSchema, {"colecao": "c"})

#respostas
def teste_resposta_minima_tem_campos_opcionais_none():
    r = _validar(RespostaProcessamentoSchema, RESPOSTA)
    assert r.conjuntos_dados is None and r.total_registros_conjuntos is None

@pytest.mark.parametrize("campo", ["arquivo", "metadados", "total_registros_validos", "colunas", "dados"])
def teste_resposta_exige_campos_basicos(campo):
    dados = {k: v for k, v in RESPOSTA.items() if k != campo}
    with pytest.raises(ValidationError):
        _validar(RespostaProcessamentoSchema, dados)

def teste_resposta_preserva_chaves_livres_nos_registros_inclusive_meta():
    registro = {"data": "2026-08-01", "km_total": 1.5, "meta_ano": 2026, "x": None}
    r = _validar(RespostaProcessamentoSchema, {**RESPOSTA, "dados": [registro]})
    assert _dump(r)["dados"] == [registro]

def teste_resposta_com_persistencia_herda_os_campos_e_persistencia_e_opcional():
    r = _validar(RespostaProcessamentoEPersistenciaSchema, RESPOSTA)
    assert r.persistencia is None
    r = _validar(RespostaProcessamentoEPersistenciaSchema,
                 {**RESPOSTA, "persistencia": {"colecao": "c", "documentos_afetados": 1}})
    assert r.persistencia.colecao == "c"

def teste_resposta_simples_ignora_o_campo_persistencia():
    r = _validar(RespostaProcessamentoSchema, {**RESPOSTA, "persistencia": {"colecao": "c", "documentos_afetados": 1}})
    assert "persistencia" not in _dump(r)

#contrato com o serviço
@pytest.mark.parametrize("chave", sorted(A.AMOSTRAS))
def teste_saida_do_servico_de_processamento_valida_no_schema(chave):
    amostra = A.AMOSTRAS[chave]
    resultado = processar_html_bytes(amostra.conteudo, amostra.arquivo)
    r = _validar(RespostaProcessamentoSchema, resultado)
    assert r.total_registros_validos == amostra.registros
    assert (r.conjuntos_dados is not None) == (chave == "saldos")

@pytest.mark.parametrize("chave", sorted(A.AMOSTRAS))
def teste_saida_do_servico_de_persistencia_valida_no_schema(db, chave):
    amostra = A.AMOSTRAS[chave]
    resultado = processar_e_persistir_html_bytes(amostra.conteudo, amostra.arquivo, db=db)
    r = _validar(RespostaProcessamentoEPersistenciaSchema, resultado)
    assert r.persistencia.colecao == amostra.colecao
    assert r.persistencia.documentos_afetados == amostra.afetados


def teste_schemas_canonicos_das_colecoes_rejeitam_snake_case_indevido():
    from datetime import datetime
    from app.services.transporte_repository import (
        COL_FINANCEIRO_SISTEMA,
        COL_PASSAGEIROS_SISTEMA,
        COL_VIAGENS_HORARIO,
        COL_VIAGENS_LINHAS,
        COL_VIAGENS_OCORRENCIAS,
        COL_VIAGENS_SISTEMA,
        validar_documento_colecao,
    )

    dt = datetime(2026, 8, 1)
    assert validar_documento_colecao(COL_VIAGENS_SISTEMA, {"data": dt, "kmTotal": 100.5}) == {
        "data": dt,
        "kmTotal": 100.5,
    }
    assert validar_documento_colecao(COL_VIAGENS_LINHAS, {"data": dt, "linha": "01", "nrViagens": 10}) == {
        "data": dt,
        "linha": "01",
        "nrViagens": 10,
    }
    assert validar_documento_colecao(COL_VIAGENS_HORARIO, {"data": dt, "linha": "01", "hora": 5, "partidas": [10, 20]}) == {
        "data": dt,
        "linha": "01",
        "hora": 5,
        "partidas": [10, 20],
    }
    assert validar_documento_colecao(
        COL_VIAGENS_OCORRENCIAS,
        {"data": dt, "linha": "01", "classificacao": "NaoRealizada", "inicioProgramado": dt},
    )["classificacao"] == "NaoRealizada"
    assert validar_documento_colecao(COL_PASSAGEIROS_SISTEMA, {"data": dt, "catraca": 50})["catraca"] == 50
    assert validar_documento_colecao(COL_FINANCEIRO_SISTEMA, {"data": dt, "totalVendas": 200.0})["totalVendas"] == 200.0

    with pytest.raises(ValidationError):
        validar_documento_colecao(COL_VIAGENS_SISTEMA, {"data": dt, "km_total": 100.5})
    with pytest.raises(ValidationError):
        validar_documento_colecao(COL_FINANCEIRO_SISTEMA, {"data": dt, "total_vendas": 200.0})