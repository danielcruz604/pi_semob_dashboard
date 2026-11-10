import bcrypt

from scripts.criar_usuarios_demo import CONTAS_DEMONSTRACAO, criar_usuarios_demo
from app.services.usuario_controller import UsuarioController


def teste_cria_todas_as_contas_com_senha_em_hash(conexao_mock):
    resultado = criar_usuarios_demo(UsuarioController())

    assert sorted(resultado["criados"]) == sorted(c["email"] for c in CONTAS_DEMONSTRACAO)
    assert resultado["existentes"] == []

    for conta in CONTAS_DEMONSTRACAO:
        doc = conexao_mock["usuarios"].find_one({"email": conta["email"]})
        assert doc is not None
        assert "senha" not in doc
        assert doc["senhaHash"] != conta["senha"]
        assert bcrypt.checkpw(conta["senha"].encode("utf-8"), doc["senhaHash"].encode("utf-8"))


def teste_reexecutar_nao_duplica_contas(conexao_mock):
    criar_usuarios_demo(UsuarioController())
    resultado = criar_usuarios_demo(UsuarioController())

    assert resultado["criados"] == []
    assert len(resultado["existentes"]) == len(CONTAS_DEMONSTRACAO)
    assert conexao_mock["usuarios"].count_documents({}) == len(CONTAS_DEMONSTRACAO)


def teste_contas_demo_conseguem_fazer_login(conexao_mock, client, monkeypatch):
    from app.routes import usuario_routes

    # O controller da rota guarda o DAO em cache; força que ele use o banco em memória deste teste.
    monkeypatch.setattr(usuario_routes.service, "_dao", None)
    criar_usuarios_demo(UsuarioController())

    for conta in CONTAS_DEMONSTRACAO:
        resposta = client.post(
            "/api/usuarios/login",
            json={"email": conta["email"], "senha": conta["senha"]},
        )
        assert resposta.status_code == 200
        dados = resposta.json()
        assert dados["usuario"]["nome"] == conta["nome"]
        assert dados["usuario"]["papel"] == conta["papel"]

        perfil = client.get(
            "/api/usuarios/perfil",
            headers={"Authorization": f"Bearer {dados['access_token']}"},
        )
        assert perfil.status_code == 200
