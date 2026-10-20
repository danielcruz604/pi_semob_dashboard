import pytest
import bcrypt
from fastapi.testclient import TestClient
from unittest.mock import patch

from app.main import app
from app.utils.token_config import criar_token_jwt

client = TestClient(app)

SENHA_TESTE = "Senha123"
hash_teste = bcrypt.hashpw(SENHA_TESTE.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')

usuario_mock = {
    "_id": "603d2b4f9f1b2c3d4e5f6a7b",
    "nome": "Teste",
    "email": "teste@teste.com",
    "senhaHash": hash_teste,
    "papel": "gestor"
}

# CENÁRIO 1: Login com sucesso e geração de Token JWT
@patch("app.services.usuario_controller.UsuarioDAO.buscar_por_email")
def test_login_com_sucesso(mock_buscar):
    mock_buscar.return_value = usuario_mock

    resposta = client.post("/usuarios/login", json={
        "email": "teste@teste.com",
        "senha": SENHA_TESTE
    })
    
    assert resposta.status_code == 200
    dados = resposta.json()
    assert "access_token" in dados
    assert dados["token_type"] == "bearer"
    assert dados["usuario"]["email"] == "teste@teste.com"


# CENÁRIO 2: Tentativa de login com senha incorreta
@patch("app.services.usuario_controller.UsuarioDAO.buscar_por_email")
def test_login_senha_incorreta(mock_buscar):
    
    mock_buscar.return_value = usuario_mock
    
    resposta = client.post("/usuarios/login", json={
        "email": "teste@teste.com",
        "senha": "Senha321"
    })
    
    assert resposta.status_code == 401
    assert resposta.json()["detail"] == "E-mail ou senha incorretos."


# CENÁRIO 3: Acesso a uma rota protegida com Token válido
def test_acesso_rota_protegida_com_token_valido():
    token_valido = criar_token_jwt({
        "sub": usuario_mock["_id"],
        "email": usuario_mock["email"],
        "papel": usuario_mock["papel"]
    })
    
    resposta = client.get("/usuarios/perfil", headers={
        "Authorization": f"Bearer {token_valido}"
    })
    
    assert resposta.status_code == 200
    assert resposta.json()["mensagem"] == "Acesso autorizado ao perfil interno do sistema"
    assert resposta.json()["dados_do_usuario"]["email"] == "teste@teste.com"


# CENÁRIO 4: Bloqueio em rota protegida por Token inválido ou ausente
def test_acesso_rota_protegida_com_token_invalido():
    token_falso = "token_falso"
    
    resposta = client.get("/usuarios/perfil", headers={
        "Authorization": f"Bearer {token_falso}"
    })
    
    assert resposta.status_code == 401
    assert resposta.json()["detail"] == "Token inválido ou adulterado."
    
    resposta_sem_token = client.get("/usuarios/perfil")
    
    assert resposta_sem_token.status_code == 401