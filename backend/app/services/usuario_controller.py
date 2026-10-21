import bcrypt
from fastapi import HTTPException
from app.dao.usuario_dao import UsuarioDAO
from app.schemas.usuario_schema import UsuarioCreate, UsuarioResponse, UsuarioLogin
from app.utils.token_config import criar_token_jwt

class UsuarioController:
    def __init__(self):
        self._dao = None

    @property
    def dao(self) -> UsuarioDAO:
        if self._dao is None:
            self._dao = UsuarioDAO()
        return self._dao

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

    def autenticar_usuario(self, credenciais: UsuarioLogin):
        usuario_db = self.dao.buscar_por_email(credenciais.email)
        
        if not usuario_db:
            raise HTTPException(status_code=401, detail="E-mail ou senha incorretos.")

        senha_valida = bcrypt.checkpw(
            credenciais.senha.encode('utf-8'),
            usuario_db["senhaHash"].encode('utf-8')
        )

        if not senha_valida:
            raise HTTPException(status_code=401, detail="E-mail ou senha incorretos.")

        dados_para_token = {
            "sub": str(usuario_db["_id"]),
            "email": usuario_db["email"],
            "papel": usuario_db["papel"]
        }
        
        token_jwt = criar_token_jwt(dados_para_token)

        # Retorna token junto com os dados para o front
        return {
            "access_token": token_jwt,
            "token_type": "bearer",
            "usuario": {
                "id": str(usuario_db["_id"]),
                "nome": usuario_db["nome"],
                "email": usuario_db["email"],
                "papel": usuario_db["papel"]
            }
        }
