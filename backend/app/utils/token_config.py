import os
import jwt
from pathlib import Path
from datetime import datetime, timedelta, timezone
from fastapi import HTTPException, Security
from dotenv import load_dotenv


BASE_DIR = Path(__file__).resolve().parent.parent.parent
ENV_PATH = BASE_DIR / ".env"

load_dotenv(dotenv_path=ENV_PATH)

SECRET_KEY = os.getenv("JWT_SECRET")
if not SECRET_KEY:
    raise ValueError("'JWT_SECRET' não configurada no ambiente.")

ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = int(os.getenv("JWT_EXPIRE_MINUTES", "480"))


# Gera o token
def criar_token_jwt(dados: dict) -> str:
    para_codificar = dados.copy()
    
    expiracao = datetime.now(timezone.utc) + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    para_codificar.update({"exp": expiracao})
    # Realiza a criação do hash final do token usando a chave secreta
    token_codificado = jwt.encode(para_codificar, SECRET_KEY, algorithm=ALGORITHM)
    return token_codificado

