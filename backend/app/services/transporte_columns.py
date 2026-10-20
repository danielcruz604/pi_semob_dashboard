import re
import unicodedata
from typing import Any, Dict, List
import pandas as pd

COLUNAS_TEXTO_ESTRITO = {
    "linha", "codigo_linha", "cod_linha", "prefixo", "atendimento",
    "atividade", "motorista", "sentido", "tabela", "serie", "faixa_horaria",
    "dia_semana", "status_saida", "status_chegada", "partidas", "mes_referencia",
    "dia", "empresa", "consorcio", "itinerario", "servico", "veiculo", "ramal",
}

COLUNAS_INTEIRAS = {
    "numero_veiculos", "numero_max_veiculos_faixa", "viagens_programadas",
    "viagens_realizadas", "diferenca_viagens", "viagens", "catraca",
    "antecipados", "nao_pagantes", "total_passageiros",
    "viagens_programadas_manha", "viagens_realizadas_manha",
    "viagens_programadas_tarde", "viagens_realizadas_tarde",
    "viagens_programadas_noite", "viagens_realizadas_noite", "programadas",
    "realizadas", "qtd", "quantidade", "total_viagens", "total_veiculos",
}

COLUNAS_DECIMAIS = {
    "km_produtivos", "km_improdutivos", "km_total", "quilometragem",
    "quilometros", "distancia", "creditos_transferidos_para_cartoes",
    "saldo_final", "total_vendas", "total_utilizacao", "credito_circulante",
    "receita", "receita_total", "arrecadacao", "faturamento", "custo",
    "custo_total", "despesa", "despesa_total", "tarifa", "valor",
    "valor_total", "percentual", "percentagem", "taxa", "media_km",
}

COLUNAS_NUMERICAS = COLUNAS_INTEIRAS | COLUNAS_DECIMAIS

COLUNAS_TRANSPORTE = {
    "data", "dia_semana", "numero_veiculos", "numero_max_veiculos_faixa",
    "viagens_programadas", "viagens_realizadas", "diferenca_viagens",
    "km_produtivos", "km_improdutivos", "km_total", "linha", "faixa_horaria",
    "viagens", "partidas", "atendimento", "prefixo", "atividade", "motorista",
    "sentido", "tabela", "status_saida", "status_chegada", "inicio_programado",
    "inicio_realizado", "fim_programado", "fim_realizado", "catraca", "antecipados",
    "nao_pagantes", "total_passageiros", "mes_referencia", "dia", "serie",
    "creditos_transferidos_para_cartoes", "saldo_final", "total_vendas",
    "total_utilizacao", "credito_circulante", "viagens_programadas_manha",
    "viagens_realizadas_manha", "viagens_programadas_tarde",
    "viagens_realizadas_tarde", "viagens_programadas_noite",
    "viagens_realizadas_noite", "programadas", "realizadas",
}

PESOS_COLUNAS_TRANSPORTE = {
    "data": 6,
    "linha": 6,
    "viagens": 5,
    "viagens_programadas": 5,
    "viagens_realizadas": 5,
    "km_total": 5,
    "km_produtivos": 4,
    "km_improdutivos": 4,
    "total_passageiros": 5,
    "catraca": 4,
    "nao_pagantes": 4,
    "saldo_final": 4,
    "total_vendas": 4,
    "credito_circulante": 4,
    "faixa_horaria": 3,
    "prefixo": 3,
    "numero_veiculos": 3,
}

CABECALHOS_GENERICOS = {
    "dados", "dado", "informacao", "informacoes", "operacao", "transporte",
    "indicador", "indicadores", "resultado", "resultados", "campo", "campos",
}

ALIASES_COLUNAS = {
    "data": "data",
    "dia_sem": "dia_semana",
    "dia_semana": "dia_semana",
    "nr_veiculos": "numero_veiculos",
    "veiculos": "numero_veiculos",
    "nr_max_veic_fx": "numero_max_veiculos_faixa",
    "nr_viagens_progr": "viagens_programadas",
    "nr_viagens_realiz": "viagens_realizadas",
    "dif_viagens": "diferenca_viagens",
    "km_prod": "km_produtivos",
    "km_improd": "km_improdutivos",
    "km_total": "km_total",
    "nr_viagens": "viagens",
    "fx_hor": "faixa_horaria",
    "linha": "linha",
    "cod_linha": "cod_linha",
    "codigo_linha": "codigo_linha",
    "codigo_da_linha": "codigo_linha",
    "codigo_da_linha_de_onibus": "codigo_linha",
    "prefixo": "prefixo",
    "atendimento": "atendimento",
    "atividade": "atividade",
    "motorista": "motorista",
    "sentido": "sentido",
    "tabela": "tabela",
    "status_saida": "status_saida",
    "status_chegada": "status_chegada",
    "inicio_programado": "inicio_programado",
    "inicio_realizado": "inicio_realizado",
    "fim_programado": "fim_programado",
    "fim_realizado": "fim_realizado",
    "manha_p": "viagens_programadas_manha",
    "manha_r": "viagens_realizadas_manha",
    "tarde_p": "viagens_programadas_tarde",
    "tarde_r": "viagens_realizadas_tarde",
    "noite_p": "viagens_programadas_noite",
    "noite_r": "viagens_realizadas_noite",
    "programadas": "viagens_programadas",
    "realizadas": "viagens_realizadas",
    "mes": "mes_referencia",
    "dia": "dia",
    "catraca": "catraca",
    "antecipados": "antecipados",
    "nao_pagantes": "nao_pagantes",
    "total_passageiros": "total_passageiros",
    "serie": "serie",
    "creditos_transferidos_para_cartoes": "creditos_transferidos_para_cartoes",
    "creditos_transferidos_para_cartoes_": "creditos_transferidos_para_cartoes",
    "saldo_final": "saldo_final",
    "total_vendas": "total_vendas",
    "total_utilizacao": "total_utilizacao",
    "credito_circulante": "credito_circulante",
    "partidas": "partidas",
    "nr_partidas": "partidas",
    "quilometragem": "quilometragem",
    "quilometros": "quilometros",
    "distancia_percorrida": "distancia",
    "valor_arrecadado": "arrecadacao",
    "receita_bruta": "receita",
    "receita_total": "receita_total",
    "total_veiculos": "total_veiculos",
    "total_viagens": "total_viagens",
    "nr_viagens_prog": "viagens_programadas",
    "nr_total_viagens_realizadas": "viagens_realizadas",
}

def normalizar_texto(valor: Any) -> str:
    if valor is None:
        return ""
    try:
        if pd.isna(valor):
            return ""
    except (TypeError, ValueError):
        pass
    texto = str(valor).strip()
    texto = unicodedata.normalize("NFKD", texto).encode("ASCII", "ignore").decode("utf-8")
    return re.sub(r"\s+", " ", texto).lower().strip()

def _normalizar_parte_coluna(valor: Any) -> str:
    texto = str(valor or "").strip()
    texto = re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", texto)
    texto = re.sub(r"([A-Z])([A-Z][a-z])", r"\1_\2", texto)
    texto = unicodedata.normalize("NFKD", texto).encode("ASCII", "ignore").decode("utf-8")
    texto = texto.lower()
    texto = re.sub(r"[^\w\s]", " ", texto)
    return re.sub(r"\s+", "_", texto).strip("_")

def normalizar_nome_coluna(coluna: Any) -> str:
    if isinstance(coluna, tuple):
        partes = []
        for item in coluna:
            parte = _normalizar_parte_coluna(item)
            if not parte or parte.startswith("unnamed"):
                continue
            tokens = [token for token in parte.split("_") if token not in CABECALHOS_GENERICOS]
            parte = "_".join(tokens)
            if parte and parte not in partes:
                partes.append(parte)
        texto = "_".join(partes)
    else:
        texto = _normalizar_parte_coluna(coluna)

    texto = re.sub(r"_+", "_", texto).strip("_")
    if texto in ALIASES_COLUNAS:
        return ALIASES_COLUNAS[texto]

    tokens = texto.split("_") if texto else []
    if len(tokens) == 2 and tokens[0] == tokens[1]:
        texto = tokens[0]
    return texto

def desduplicar_colunas(colunas: List[str]) -> List[str]:
    usados: set = set()
    contadores: Dict[str, int] = {}
    novas_colunas: List[str] = []
    for col in colunas:
        base = (col or "").strip() or "coluna"
        nome = base
        while nome in usados:
            contadores[base] = contadores.get(base, 0) + 1
            nome = f"{base}_{contadores[base]}"
        usados.add(nome)
        novas_colunas.append(nome)
    return novas_colunas

def nome_coluna_base(coluna: str) -> str:
    return re.sub(r"_\d+$", "", coluna)

def coluna_eh_texto_estrito(coluna: str) -> bool:
    return nome_coluna_base(coluna) in COLUNAS_TEXTO_ESTRITO

def coluna_eh_inteira(coluna: str) -> bool:
    return nome_coluna_base(coluna) in COLUNAS_INTEIRAS

def coluna_eh_numerica(coluna: str) -> bool:
    return nome_coluna_base(coluna) in COLUNAS_NUMERICAS