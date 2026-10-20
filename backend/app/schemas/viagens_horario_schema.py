from pydantic import BaseModel
from datetime import date
from typing import List

class ViagensHorarioCreate(BaseModel):
    data: date
    linha: str
    hora: int
    nrVeiculos: int
    nrViagens: int
    partidas: List[int]

class ViagensHorarioResponse(ViagensHorarioCreate):
    id: str
