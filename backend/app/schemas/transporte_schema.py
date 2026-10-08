from typing import Any, Dict, List, Optional
from pydantic import BaseModel

class MetadadosSchema(BaseModel):
    tipo_relatorio: str
    periodicidade: Optional[str] = None
    ano: Optional[int] = None
    mes: Optional[int] = None
    semana: Optional[int] = None
    data: Optional[str] = None

class RespostaProcessamentoSchema(BaseModel):
    arquivo: str
    metadados: MetadadosSchema
    total_registros_validos: int
    colunas: List[str]
    dados: List[Dict[str, Any]]