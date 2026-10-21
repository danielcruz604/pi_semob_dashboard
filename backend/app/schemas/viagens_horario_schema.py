from datetime import datetime
from typing import List, Optional
from pydantic import BaseModel, ConfigDict, Field


class ViagensHorarioCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    data: datetime
    linha: str
    hora: int
    nrVeiculos: Optional[int] = None
    nrViagens: Optional[int] = None
    partidas: Optional[List[int]] = None


class ViagensHorarioResponse(ViagensHorarioCreate):
    id: Optional[str] = Field(default=None, alias="_id")
