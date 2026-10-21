from typing import Any, Dict, List, Sequence, Type
from pydantic import BaseModel
from pymongo import UpdateOne
from pymongo.database import Database
from app.schemas.financeiro_sistema_schema import FinanceiroSistemaCreate
from app.schemas.passageiros_sistema_schema import PassageirosSistemaCreate
from app.schemas.viagens_horario_schema import ViagensHorarioCreate
from app.schemas.viagens_linhas_schema import ViagensLinhasCreate
from app.schemas.viagens_ocorrencias_schema import ViagensOcorrenciasCreate
from app.schemas.viagens_sistema_schema import ViagensSistemaCreate

COL_VIAGENS_SISTEMA = "viagensSistema"
COL_VIAGENS_LINHAS = "viagensLinhas"
COL_VIAGENS_HORARIO = "viagensHorario"
COL_VIAGENS_OCORRENCIAS = "viagensOcorrencias"
COL_PASSAGEIROS_SISTEMA = "passageirosSistema"
COL_FINANCEIRO_SISTEMA = "financeiroSistema"

CHAVES_UNICAS: Dict[str, Sequence[str]] = {
    COL_VIAGENS_SISTEMA: ("data",),
    COL_VIAGENS_LINHAS: ("data", "linha"),
    COL_VIAGENS_HORARIO: ("data", "linha", "hora"),
    COL_VIAGENS_OCORRENCIAS: ("data", "linha", "prefixo", "inicioProgramado", "classificacao"),
    COL_PASSAGEIROS_SISTEMA: ("data",),
    COL_FINANCEIRO_SISTEMA: ("data",),
}

SCHEMAS_COLECAO: Dict[str, Type[BaseModel]] = {
    COL_VIAGENS_SISTEMA: ViagensSistemaCreate,
    COL_VIAGENS_LINHAS: ViagensLinhasCreate,
    COL_VIAGENS_HORARIO: ViagensHorarioCreate,
    COL_VIAGENS_OCORRENCIAS: ViagensOcorrenciasCreate,
    COL_PASSAGEIROS_SISTEMA: PassageirosSistemaCreate,
    COL_FINANCEIRO_SISTEMA: FinanceiroSistemaCreate,
}


def validar_documento_colecao(colecao: str, documento: Dict[str, Any]) -> Dict[str, Any]:
    """Valida o documento parcial contra o schema canônico da coleção antes do upsert."""
    schema_cls = SCHEMAS_COLECAO.get(colecao)
    if schema_cls is None:
        return documento
    instancia = schema_cls.model_validate(documento)
    return instancia.model_dump(exclude_unset=True)


def garantir_indices(db: Database) -> None:
    #Cria índices únicos nas chaves de upsert. Chamar no startup da aplicação. Falha se já existirem duplicatas: limpe-as antes.
    for colecao, campos in CHAVES_UNICAS.items():
        db[colecao].create_index(
            [(campo, 1) for campo in campos],
            unique=True,
            name="uq_" + "_".join(campos),
        )


def _achatar(documento: Dict[str, Any], prefixo: str = "") -> Dict[str, Any]:
    plano: Dict[str, Any] = {}
    for chave, valor in documento.items():
        caminho = f"{prefixo}{chave}"
        if isinstance(valor, dict):
            plano.update(_achatar(valor, f"{caminho}."))
        elif valor is not None:
            plano[caminho] = valor
    return plano


def _upsert(db: Database, colecao: str, documentos: List[Dict[str, Any]]) -> int:
    if not documentos:
        return 0
    chaves = CHAVES_UNICAS[colecao]
    docs_validados = [validar_documento_colecao(colecao, doc) for doc in documentos]
    operacoes = [
        UpdateOne(
            {chave: doc.get(chave) for chave in chaves},
            {"$set": _achatar(doc)},
            upsert=True,
        )
        for doc in docs_validados
    ]
    resultado = db[colecao].bulk_write(operacoes, ordered=False)
    return resultado.upserted_count + resultado.modified_count


def upsert_viagens_sistema(db: Database, documentos: List[Dict[str, Any]]) -> int:
    return _upsert(db, COL_VIAGENS_SISTEMA, documentos)


def upsert_viagens_linhas(db: Database, documentos: List[Dict[str, Any]]) -> int:
    return _upsert(db, COL_VIAGENS_LINHAS, documentos)


def upsert_viagens_horario(db: Database, documentos: List[Dict[str, Any]]) -> int:
    return _upsert(db, COL_VIAGENS_HORARIO, documentos)


def upsert_viagens_ocorrencias(db: Database, documentos: List[Dict[str, Any]]) -> int:
    return _upsert(db, COL_VIAGENS_OCORRENCIAS, documentos)


def upsert_passageiros_sistema(db: Database, documentos: List[Dict[str, Any]]) -> int:
    return _upsert(db, COL_PASSAGEIROS_SISTEMA, documentos)


def upsert_financeiro_sistema(db: Database, documentos: List[Dict[str, Any]]) -> int:
    return _upsert(db, COL_FINANCEIRO_SISTEMA, documentos)
