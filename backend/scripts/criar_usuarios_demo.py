"""Cadastra no MongoDB as contas de demonstração usadas na tela de login.

Uso (a partir da pasta backend/, com o .env configurado):

    python -m scripts.criar_usuarios_demo

O script é idempotente: contas que já existem são mantidas sem alteração.
"""

from app.schemas.usuario_schema import UsuarioCreate
from app.services.usuario_controller import UsuarioController
from app.utils.connection_factory import ConnectionFactory

CONTAS_DEMONSTRACAO = [
    {
        "nome": "Diretoria Geral",
        "email": "gestor@semob.sp.gov.br",
        "senha": "semob2026",
        "papel": "gestor",
    },
    {
        "nome": "Engenharia de Tráfego",
        "email": "analista@semob.sp.gov.br",
        "senha": "transporte123",
        "papel": "analista",
    },
    {
        "nome": "Fiscalização de Frota",
        "email": "fiscal@semob.sp.gov.br",
        "senha": "fiscal2026",
        "papel": "fiscal",
    },
]


def criar_usuarios_demo(controller: UsuarioController | None = None) -> dict:
    """Cria as contas que ainda não existem e retorna o que foi feito."""
    controller = controller or UsuarioController()
    criados, existentes = [], []

    for conta in CONTAS_DEMONSTRACAO:
        if controller.dao.buscar_por_email(conta["email"]):
            existentes.append(conta["email"])
            continue
        controller.registrar_usuario(UsuarioCreate(**conta))
        criados.append(conta["email"])

    return {"criados": criados, "existentes": existentes}


def main() -> None:
    try:
        resultado = criar_usuarios_demo()
    finally:
        ConnectionFactory().close()

    for email in resultado["criados"]:
        print(f"[criado]    {email}")
    for email in resultado["existentes"]:
        print(f"[existente] {email}")


if __name__ == "__main__":
    main()
