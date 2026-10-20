from pydantic import BaseModel
from datetime import date

class FcvPeriodo(BaseModel):
    prog: int
    real: int
    fcv: float

class FcvPorPeriodo(BaseModel):
    manha: FcvPeriodo
    tarde: FcvPeriodo
    noite: FcvPeriodo

class ViagensSistemaCreate(BaseModel):
    data: date
    diaSem: str
    nrVeiculos: int
    nrMaxVeicFx: int
    nrViagensProg: int
    nrTotalViagensRealizadas: int
    fcvTotal: float
    fcvPorPeriodo: FcvPorPeriodo
    kmProdTotal: float
    kmImprodTotal: float
    kmTotal: float

class ViagensSistemaResponse(ViagensSistemaCreate):
    id: str
