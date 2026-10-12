import json
from typing import Any, Dict
from app.services.transporte_cleaner import higienizar_dataframe
from app.services.transporte_metadata import extrair_metadados_nome_arquivo
from app.services.transporte_tables import (
    ler_tabelas_html,
    selecionar_tabela_principal,
)

def processar_html_bytes(
    conteudo_bytes: bytes,
    nome_arquivo: str,
) -> Dict[str, Any]:
    tabelas = ler_tabelas_html(
        conteudo_bytes
    )

    if not tabelas:
        raise ValueError(
            "Nenhuma tabela encontrada no arquivo."
        )

    metadados = (
        extrair_metadados_nome_arquivo(
            nome_arquivo
        )
    )

    df_bruto = (
        selecionar_tabela_principal(
            tabelas
        )
    )

    df_processado = (
        higienizar_dataframe(
            df_bruto,
            metadados,
        )
    )

    if df_processado.empty:
        raise ValueError(
            "A tabela não possui registros válidos após a higienização."
        )

    dados_finais = json.loads(
        df_processado.to_json(
            orient="records",
            date_format="iso",
        )
    )

    return {
        "arquivo": nome_arquivo,
        "metadados": metadados,
        "total_registros_validos": len(
            dados_finais
        ),
        "colunas": list(
            df_processado.columns
        ),
        "dados": dados_finais,
    }