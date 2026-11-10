"""Proteção das rotas da API com JWT.

Garante que toda rota de dados exige um token válido, que apenas login e status são
públicos e que o cadastro de usuários é restrito ao papel gestor.
"""

from datetime import datetime, timedelta, timezone

import jwt
import pytest
from fastapi.testclient import TestClient

from auth_helpers import cabecalho_autenticado, token_valido
from main import app
from app.utils.token_config import ALGORITHM, SECRET_KEY

ROTAS_PUBLICAS = {
    ("GET", "/"),
    ("POST", "/api/usuarios/login"),
}


def _operacoes_da_api():
    """(método, caminho, operação) de cada rota documentada no OpenAPI.

    Usar o schema OpenAPI mantém o teste independente da forma como cada versão do
    FastAPI organiza internamente os routers incluídos.
    """
    operacoes = []
    for caminho, metodos in app.openapi()["paths"].items():
        for metodo, operacao in metodos.items():
            operacoes.append((metodo.upper(), caminho, operacao))
    return sorted(operacoes, key=lambda o: (o[1], o[0]))


def _exige_bearer(operacao) -> bool:
    return any("HTTPBearer" in requisito for requisito in operacao.get("security", []))


ROTAS_PROTEGIDAS = [
    (metodo, caminho) for metodo, caminho, _ in _operacoes_da_api() if (metodo, caminho) not in ROTAS_PUBLICAS
]


@pytest.fixture
def cliente_anonimo():
    return TestClient(app, raise_server_exceptions=False)


def _requisitar(cliente, metodo, caminho, headers=None):
    return cliente.request(metodo, caminho, headers=headers or {})


def _token_expirado() -> str:
    dados = {
        "sub": "usuario-gestor",
        "email": "gestor@semob.sp.gov.br",
        "papel": "gestor",
        "exp": datetime.now(timezone.utc) - timedelta(minutes=1),
    }
    return jwt.encode(dados, SECRET_KEY, algorithm=ALGORITHM)


def teste_existem_rotas_protegidas_para_verificar():
    caminhos = {caminho for _, caminho in ROTAS_PROTEGIDAS}
    assert "/api/dashboard/resumo-operacional" in caminhos
    assert "/api/transporte/processar-e-salvar" in caminhos
    assert "/api/v1/relatorios/upload" in caminhos
    assert "/api/usuarios/perfil" in caminhos


@pytest.mark.parametrize(
    "metodo,caminho,operacao",
    _operacoes_da_api(),
    ids=[f"{m} {c}" for m, c, _ in _operacoes_da_api()],
)
def teste_toda_rota_nao_publica_exige_token_bearer(metodo, caminho, operacao):
    """Protege contra rotas novas criadas sem autenticação."""
    if (metodo, caminho) in ROTAS_PUBLICAS:
        assert not _exige_bearer(operacao), f"{metodo} {caminho} deveria ser pública"
    else:
        assert _exige_bearer(operacao), f"{metodo} {caminho} está sem proteção JWT"


@pytest.mark.parametrize("metodo,caminho", ROTAS_PROTEGIDAS)
def teste_rota_protegida_sem_token_retorna_401(cliente_anonimo, metodo, caminho):
    resposta = _requisitar(cliente_anonimo, metodo, caminho)

    assert resposta.status_code == 401
    assert resposta.headers.get("www-authenticate") == "Bearer"
    assert resposta.json()["detail"] == "Token de acesso ausente. Faça login para continuar."


@pytest.mark.parametrize("metodo,caminho", ROTAS_PROTEGIDAS)
def teste_rota_protegida_com_token_adulterado_retorna_401(cliente_anonimo, metodo, caminho):
    resposta = _requisitar(cliente_anonimo, metodo, caminho, {"Authorization": "Bearer token.invalido.qualquer"})

    assert resposta.status_code == 401
    assert resposta.json()["detail"] == "Token inválido ou adulterado."


@pytest.mark.parametrize("metodo,caminho", ROTAS_PROTEGIDAS)
def teste_rota_protegida_com_token_expirado_retorna_401(cliente_anonimo, metodo, caminho):
    resposta = _requisitar(cliente_anonimo, metodo, caminho, {"Authorization": f"Bearer {_token_expirado()}"})

    assert resposta.status_code == 401
    assert resposta.json()["detail"] == "Token expirado. Faça login novamente."


def teste_token_assinado_com_outra_chave_e_recusado(cliente_anonimo):
    falso = jwt.encode(
        {"sub": "invasor", "papel": "gestor", "exp": datetime.now(timezone.utc) + timedelta(hours=1)},
        "outra-chave-que-nao-e-a-do-servidor-32b",
        algorithm=ALGORITHM,
    )
    resposta = cliente_anonimo.get("/api/dashboard/filtros", headers={"Authorization": f"Bearer {falso}"})

    assert resposta.status_code == 401


def teste_esquema_diferente_de_bearer_e_recusado(cliente_anonimo):
    resposta = cliente_anonimo.get("/api/dashboard/filtros", headers={"Authorization": f"Basic {token_valido()}"})

    assert resposta.status_code == 401


def teste_rota_protegida_com_token_valido_e_atendida(cliente_anonimo, conexao_mock):
    resposta = cliente_anonimo.get("/api/dashboard/filtros", headers=cabecalho_autenticado("analista"))

    assert resposta.status_code == 200


def teste_status_continua_publico(cliente_anonimo):
    resposta = cliente_anonimo.get("/")

    assert resposta.status_code == 200


def teste_login_continua_publico(cliente_anonimo):
    resposta = cliente_anonimo.post("/api/usuarios/login", json={"email": "invalido"})

    # 422 = a requisição passou da camada de autenticação e falhou só na validação do corpo.
    assert resposta.status_code == 422


# ----------------------------------------------------------------- cadastro de usuários

NOVO_USUARIO = {
    "nome": "Nova Analista",
    "email": "nova.analista@semob.sp.gov.br",
    "senha": "senha-forte-123",
    "papel": "analista",
}


@pytest.fixture
def cadastro_em_memoria(conexao_mock, monkeypatch):
    from app.routes import usuario_routes

    # O controller da rota guarda o DAO em cache; força o uso do banco em memória deste teste.
    monkeypatch.setattr(usuario_routes.service, "_dao", None)
    return conexao_mock


def teste_cadastro_sem_token_retorna_401(cliente_anonimo, cadastro_em_memoria):
    resposta = cliente_anonimo.post("/api/usuarios/", json=NOVO_USUARIO)

    assert resposta.status_code == 401
    assert cadastro_em_memoria["usuarios"].count_documents({}) == 0


@pytest.mark.parametrize("papel", ["analista", "fiscal"])
def teste_cadastro_por_quem_nao_e_gestor_retorna_403(cliente_anonimo, cadastro_em_memoria, papel):
    resposta = cliente_anonimo.post("/api/usuarios/", json=NOVO_USUARIO, headers=cabecalho_autenticado(papel))

    assert resposta.status_code == 403
    assert resposta.json()["detail"] == "Acesso restrito ao perfil: gestor."
    assert cadastro_em_memoria["usuarios"].count_documents({}) == 0


def teste_cadastro_por_gestor_cria_usuario(cliente_anonimo, cadastro_em_memoria):
    resposta = cliente_anonimo.post("/api/usuarios/", json=NOVO_USUARIO, headers=cabecalho_autenticado("gestor"))

    assert resposta.status_code == 201
    assert resposta.json()["email"] == NOVO_USUARIO["email"]
    doc = cadastro_em_memoria["usuarios"].find_one({"email": NOVO_USUARIO["email"]})
    assert doc is not None
    assert "senha" not in doc
