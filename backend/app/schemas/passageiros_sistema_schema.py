from pydantic import BaseModel
from datetime import date

class PassageirosSistemaCreate(BaseModel):
    data: date
    catraca: int
    antecipados: int
    naoPagantes: int
    totalPassageiros: int

class PassageirosSistemaResponse(PassageirosSistemaCreate):
    id: str
