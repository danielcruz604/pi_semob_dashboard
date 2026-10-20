from pydantic import BaseModel
from datetime import date

class FinanceiroSistemaCreate(BaseModel):
    data: date
    serie: int
    creditosTransferidosParaCartoes: float
    saldoFinal: float
    totalVendas: float
    totalUtilizacao: float
    creditoCirculante: float

class FinanceiroSistemaResponse(FinanceiroSistemaCreate):
    id: str
