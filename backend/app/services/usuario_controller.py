import bcrypt
from fastapi import HTTPException
from backend.app.dao.usuario_dao import UsuarioDAO
from app.schemas.usuario_schema import UsuarioCreate, UsuarioResponse, UsuarioLogin
from app.utils.token_config import criar_token_jwt

class UsuarioController:
    def __init__(self):
        self.dao = UsuarioDAO()

    def registrar_usuario(self, dados: UsuarioCreate) -> UsuarioResponse:
        if self.dao.buscar_por_email(dados.email):
            raise HTTPException(status_code=400, detail="E-mail já cadastrado.")

        salt = bcrypt.gensalt()
        senha_hash = bcrypt.hashpw(dados.senha.encode('utf-8'), salt).decode('utf-8')

        novo_usuario = {
            "nome": dados.nome,
            "email": dados.email,
            "senhaHash": senha_hash,
            "papel": dados.papel
        }

        
        id_inserido = self.dao.inserir(novo_usuario)

        return UsuarioResponse(
            id=id_inserido,
            nome=dados.nome,
            email=dados.email,
            papel=dados.papel
        )

