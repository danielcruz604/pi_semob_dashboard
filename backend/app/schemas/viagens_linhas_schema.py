from datetime import datetime
from typing import Optional
from pydantic import BaseModel, ConfigDict, Field


class ViagensLinhasCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    data: datetime
    linha: str
    kmTotal: Optional[float] = None
    nrViagens: Optional[int] = None


class ViagensLinhasResponse(ViagensLinhasCreate):
    id: Optional[str] = Field(default=None, alias="_id")
