from pydantic import BaseModel, EmailStr, Field

class UsuarioCreate(BaseModel):
    nome: str = Field(..., min_length=2)
    email: EmailStr
    senha: str = Field(..., min_length=6)
    papel: str

class UsuarioResponse(BaseModel):
    id: str
    nome: str
    email: str
    papel: str
