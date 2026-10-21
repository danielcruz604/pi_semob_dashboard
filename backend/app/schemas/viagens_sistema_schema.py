from datetime import datetime
from typing import Optional
from pydantic import BaseModel, ConfigDict, Field


class FcvPeriodo(BaseModel):
    model_config = ConfigDict(extra="forbid")
    prog: int
    real: int
    fcv: float

class FcvPorPeriodo(BaseModel):
    model_config = ConfigDict(extra="forbid")

    manha: Optional[FcvPeriodo] = None
    tarde: Optional[FcvPeriodo] = None
    noite: Optional[FcvPeriodo] = None


class ViagensSistemaCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    data: datetime
    diaSem: Optional[str] = None
    nrVeiculos: Optional[int] = None
    nrMaxVeicFx: Optional[int] = None
    nrViagensProg: Optional[int] = None
    nrTotalViagensRealizadas: Optional[int] = None
    fcvTotal: Optional[float] = None
    fcvPorPeriodo: Optional[FcvPorPeriodo] = None
    kmProdTotal: Optional[float] = None
    kmImprodTotal: Optional[float] = None
    kmTotal: Optional[float] = None


class ViagensSistemaResponse(ViagensSistemaCreate):
    id: Optional[str] = Field(default=None, alias="_id")
