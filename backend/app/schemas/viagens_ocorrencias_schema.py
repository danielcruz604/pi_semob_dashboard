from pydantic import BaseModel
from datetime import date, datetime

class ViagensOcorrenciasCreate(BaseModel):
    data: date
    classificacao: str
    linha: str
    atendimento: str
    prefixo: int
    atividade: str
    motorista: int
    sentido: str
    tabela: str
    statusSaida: str
    statusChegada: str
    inicioProgramado: datetime
    inicioRealizado: datetime
    fimProgramado: datetime
    fimRealizado: datetime
    kmProd: float

class ViagensOcorrenciasResponse(ViagensOcorrenciasCreate):
    id: str
