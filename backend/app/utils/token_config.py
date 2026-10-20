import os
import jwt
from pathlib import Path
from datetime import datetime, timedelta, timezone
from fastapi import HTTPException, Security
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from dotenv import load_dotenv


BASE_DIR = Path(__file__).resolve().parent.parent.parent
ENV_PATH = BASE_DIR / ".env"

load_dotenv(dotenv_path=ENV_PATH)

SECRET_KEY = os.getenv("JWT_SECRET")
if not SECRET_KEY:
    raise ValueError("'JWT_SECRET' não configurada no ambiente.")

ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = int(os.getenv("JWT_EXPIRE_MINUTES", "480"))

# Realiza leitura do cabeçalho "Authorization: Bearer <token>"
security = HTTPBearer()

# Gera o token
def criar_token_jwt(dados: dict) -> str:
    para_codificar = dados.copy()
    
    expiracao = datetime.now(timezone.utc) + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    para_codificar.update({"exp": expiracao})
    # Realiza a criação do hash final do token usando a chave secreta
    token_codificado = jwt.encode(para_codificar, SECRET_KEY, algorithm=ALGORITHM)
    return token_codificado

#intercepta a requisição, extrai o token e verifica se é válido.
def verificar_token(credenciais: HTTPAuthorizationCredentials = Security(security)) -> dict:
    token = credenciais.credentials
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        # Realiza a devolução dos dados de dentro do token
        return payload 
        
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expirado. Faça login novamente.")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Token inválido ou adulterado.")
