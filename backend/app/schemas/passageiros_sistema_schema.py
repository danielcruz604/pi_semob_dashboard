from datetime import datetime
from typing import Optional
from pydantic import BaseModel, ConfigDict, Field


class PassageirosSistemaCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    data: datetime
    catraca: Optional[int] = None
    antecipados: Optional[int] = None
    naoPagantes: Optional[int] = None
    totalPassageiros: Optional[int] = None


class PassageirosSistemaResponse(PassageirosSistemaCreate):
    id: Optional[str] = Field(default=None, alias="_id")
