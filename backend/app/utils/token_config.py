import logging
import os
import jwt
from pathlib import Path
from datetime import datetime, timedelta, timezone
from typing import Optional
from fastapi import Depends, HTTPException, Security
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from dotenv import load_dotenv

logger = logging.getLogger(__name__)


BASE_DIR = Path(__file__).resolve().parent.parent.parent
ENV_PATH = BASE_DIR / ".env"

load_dotenv(dotenv_path=ENV_PATH)

SECRET_KEY = os.getenv("JWT_SECRET") or "semob_dev_test_secret_key_fallback_32bytes"
if not os.getenv("JWT_SECRET"):
    logger.warning(
        "JWT_SECRET não definido: usando a chave de desenvolvimento. "
        "Defina JWT_SECRET no .env antes de publicar a API."
    )

ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = int(os.getenv("JWT_EXPIRE_MINUTES", "480"))

# Realiza leitura do cabeçalho "Authorization: Bearer <token>".
# auto_error=False deixa a ausência do token sob nosso controle, garantindo HTTP 401
# (e não 403, como fazem versões antigas do FastAPI) em qualquer versão suportada.
security = HTTPBearer(auto_error=False)

# Gera o token
def criar_token_jwt(dados: dict) -> str:
    para_codificar = dados.copy()
    
    expiracao = datetime.now(timezone.utc) + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    para_codificar.update({"exp": expiracao})
    # Realiza a criação do hash final do token usando a chave secreta
    token_codificado = jwt.encode(para_codificar, SECRET_KEY, algorithm=ALGORITHM)
    return token_codificado

def _nao_autenticado(mensagem: str) -> HTTPException:
    return HTTPException(
        status_code=401,
        detail=mensagem,
        headers={"WWW-Authenticate": "Bearer"},
    )


# Intercepta a requisição, extrai o token e verifica se é válido.
def verificar_token(
    credenciais: Optional[HTTPAuthorizationCredentials] = Security(security),
) -> dict:
    if credenciais is None or not credenciais.credentials:
        raise _nao_autenticado("Token de acesso ausente. Faça login para continuar.")

    token = credenciais.credentials
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        # Realiza a devolução dos dados de dentro do token
        return payload

    except jwt.ExpiredSignatureError:
        raise _nao_autenticado("Token expirado. Faça login novamente.")
    except jwt.InvalidTokenError:
        raise _nao_autenticado("Token inválido ou adulterado.")


def exigir_papel(*papeis_permitidos: str):
    """Dependência que exige um token válido e um dos papéis informados (HTTP 403 caso contrário)."""

    def _verificar_papel(usuario: dict = Depends(verificar_token)) -> dict:
        if usuario.get("papel") not in papeis_permitidos:
            raise HTTPException(
                status_code=403,
                detail="Acesso restrito ao perfil: " + ", ".join(papeis_permitidos) + ".",
            )
        return usuario

    return _verificar_papel


# Use em routers e rotas que exigem usuário autenticado: dependencies=ROTA_PROTEGIDA
ROTA_PROTEGIDA = [Depends(verificar_token)]
