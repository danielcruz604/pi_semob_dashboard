from fastapi.testclient import TestClient
from main import app

client = TestClient(app)
ARQUIVO_TESTE = "Saldos_Mensal.html"  # Substitua pelo seu arquivo

def test_processar_html_real():
    with open(ARQUIVO_TESTE, "rb") as f:
        resposta = client.post(
            "/api/transporte/processar-html",
            files={"file": (ARQUIVO_TESTE, f, "text/html")}
        )

    assert resposta.status_code == 200
    dados = resposta.json()
    assert dados["total_registros_validos"] > 0
    assert len(dados["dados"]) > 0

def test_arquivo_invalido():
    resposta = client.post(
        "/api/transporte/processar-html",
        files={"file": ("invalido.txt", b"teste", "text/plain")}
    )
    assert resposta.status_code == 400