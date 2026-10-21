from datetime import datetime
from typing import Optional
from pydantic import BaseModel, ConfigDict, Field


class ViagensOcorrenciasCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    data: datetime
    classificacao: str
    linha: str
    atendimento: Optional[str] = None
    prefixo: Optional[int] = None
    atividade: Optional[str] = None
    motorista: Optional[int] = None
    sentido: Optional[str] = None
    tabela: Optional[str] = None
    statusSaida: Optional[str] = None
    statusChegada: Optional[str] = None
    inicioProgramado: datetime
    inicioRealizado: Optional[datetime] = None
    fimProgramado: Optional[datetime] = None
    fimRealizado: Optional[datetime] = None
    kmProd: Optional[float] = None


class ViagensOcorrenciasResponse(ViagensOcorrenciasCreate):
    id: Optional[str] = Field(default=None, alias="_id")
