"""Utilitários de autenticação compartilhados pelos testes."""

from app.utils.token_config import criar_token_jwt


def token_valido(papel: str = "gestor", **extras) -> str:
    """Gera um JWT válido para o papel informado."""
    dados = {"sub": f"usuario-{papel}", "email": f"{papel}@semob.sp.gov.br", "papel": papel}
    dados.update(extras)
    return criar_token_jwt(dados)


def cabecalho_autenticado(papel: str = "gestor") -> dict:
    """Cabeçalho Authorization com um JWT válido para o papel informado."""
    return {"Authorization": f"Bearer {token_valido(papel)}"}
