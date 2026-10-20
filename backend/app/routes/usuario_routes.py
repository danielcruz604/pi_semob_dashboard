from fastapi import APIRouter, Depends
from app.schemas.usuario_schema import UsuarioCreate, UsuarioResponse
from app.services.usuario_controller import UsuarioController
from app.schemas.usuario_schema import UsuarioLogin
from app.utils.token_config import verificar_token

router = APIRouter(prefix="/usuarios", tags=["Usuários"])
service = UsuarioController()

@router.post("/", response_model=UsuarioResponse, status_code=201)
def criar_usuario(usuario: UsuarioCreate):
    return service.registrar_usuario(usuario)

@router.post("/login")
def login_usuario(credenciais: UsuarioLogin):
    return service.autenticar_usuario(credenciais)

