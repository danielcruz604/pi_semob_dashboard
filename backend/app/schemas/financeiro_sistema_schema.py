from datetime import datetime
from typing import Optional
from pydantic import BaseModel, ConfigDict, Field


class FinanceiroSistemaCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    data: datetime
    serie: Optional[int] = None
    creditosTransferidosParaCartoes: Optional[float] = None
    saldoFinal: Optional[float] = None
    totalVendas: Optional[float] = None
    totalUtilizacao: Optional[float] = None
    creditoCirculante: Optional[float] = None


class FinanceiroSistemaResponse(FinanceiroSistemaCreate):
    id: Optional[str] = Field(default=None, alias="_id")
