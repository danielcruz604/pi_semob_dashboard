from fastapi import APIRouter, Depends
from app.schemas.usuario_schema import UsuarioCreate, UsuarioResponse
from app.services.usuario_controller import UsuarioController
from app.schemas.usuario_schema import UsuarioLogin
from app.utils.token_config import exigir_papel, verificar_token

router = APIRouter(prefix="/usuarios", tags=["Usuários"])
service = UsuarioController()

# Somente gestores podem cadastrar novos usuários.
@router.post("/", response_model=UsuarioResponse, status_code=201)
def criar_usuario(usuario: UsuarioCreate, _gestor: dict = Depends(exigir_papel("gestor"))):
    return service.registrar_usuario(usuario)

@router.post("/login")
def login_usuario(credenciais: UsuarioLogin):
    return service.autenticar_usuario(credenciais)

@router.get("/perfil")
def buscar_perfil(usuario_logado: dict = Depends(verificar_token)):
    return {
        "mensagem": "Acesso autorizado ao perfil interno do sistema",
        "dados_do_usuario": usuario_logado
    }
