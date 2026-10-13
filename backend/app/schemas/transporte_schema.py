from typing import Any, Dict, List, Optional
from pydantic import BaseModel

class MetadadosSchema(BaseModel):
    tipo_relatorio: str
    periodicidade: Optional[str] = None
    ano: Optional[int] = None
    mes: Optional[int] = None
    semana: Optional[int] = None
    data: Optional[str] = None
    data_inicio: Optional[str] = None
    data_fim: Optional[str] = None

class ConjuntoDadosSchema(BaseModel):
    nome: str
    colunas: List[str]
    total_registros_validos: int
    dados: List[Dict[str, Any]]

class RespostaProcessamentoSchema(BaseModel):
    arquivo: str
    metadados: MetadadosSchema
    total_registros_validos: int
    colunas: List[str]
    dados: List[Dict[str, Any]]
    conjuntos_dados: Optional[List[ConjuntoDadosSchema]] = None
    total_registros_conjuntos: Optional[int] = None

class PersistenciaSchema(BaseModel):
    colecao: str
    documentos_afetados: int
    registros_descartados: Optional[int] = None

class RespostaProcessamentoEPersistenciaSchema(RespostaProcessamentoSchema):
    persistencia: Optional[PersistenciaSchema] = None