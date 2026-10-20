from pydantic import BaseModel
from datetime import date

class ViagensLinhasCreate(BaseModel):
    data: date
    linha: str
    kmTotal: float
    nrViagens: int

class ViagensLinhasResponse(ViagensLinhasCreate):
    id: str
