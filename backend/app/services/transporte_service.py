import io
import json
import re
import unicodedata
from datetime import datetime
from typing import Any, Dict, List, Optional
import pandas as pd

COLUNAS_TEXTO_ESTRITO = {
    "linha", "cod_linha", "codigo", "codigo_linha", "prefixo", "servico",
    "empresa", "consorcio", "itinerario", "sentido", "faixa_horaria",
    "veiculo", "codigo_veiculo", "id", "id_linha", "id_veiculo", "ramal"
}

COLUNAS_INTEIRAS = {
    "viagens", "passageiros", "passageiros_pagantes", "passageiros_nao_pagantes",
    "pagantes", "nao_pagantes", "quantidade", "qtd"
}

COLUNAS_NUMERICAS = {
    "quilometragem", "quilometros", "km", "distancia", "receita", "arrecadacao",
    "faturamento", "custo", "despesa", "tarifa", "valor", "percentual",
    "percentagem", "taxa", "media", "media_km", "total"
}

COLUNAS_TRANSPORTE = {
    "linha", "cod_linha", "codigo", "codigo_linha", "prefixo", "servico",
    "empresa", "consorcio", "itinerario", "sentido", "faixa_horaria", "horario",
    "data", "viagens", "passageiros", "passageiros_pagantes",
    "passageiros_nao_pagantes", "quilometragem", "quilometros", "km", "distancia",
    "receita", "arrecadacao", "faturamento", "custo", "despesa", "tarifa", "valor"
}

PESOS_COLUNAS_TRANSPORTE = {
    "linha": 6,
    "codigo_linha": 5,
    "cod_linha": 5,
    "prefixo": 5,
    "data": 5,
    "viagens": 5,
    "passageiros": 5,
    "passageiros_pagantes": 5,
    "passageiros_nao_pagantes": 5,
    "quilometragem": 5,
    "empresa": 4,
    "servico": 4,
    "sentido": 3,
    "itinerario": 3,
    "receita": 3,
    "arrecadacao": 3,
    "faturamento": 3,
    "custo": 3,
    "despesa": 3,
    "tarifa": 3,
    "valor": 2,
    "horario": 2,
    "faixa_horaria": 2,
    "consorcio": 2,
    "distancia": 2,
    "km": 2,
}

CABECALHOS_GENERICOS = {
    "dados", "informacao", "informacoes", "operacao", "transporte",
    "indicador", "indicadores", "resultado", "resultados", "campo", "campos"
}

ALIASES_COLUNAS = {
    "codigo da linha": "codigo_linha",
    "codigo_linha": "codigo_linha",
    "cod da linha": "cod_linha",
    "cod_linha": "cod_linha",
    "passageiros pagantes": "passageiros_pagantes",
    "passageiros nao pagantes": "passageiros_nao_pagantes",
    "passageiros pagantes": "passageiros_pagantes",
    "passageiros naopagantes": "passageiros_nao_pagantes",
    "quilometragem": "quilometragem",
    "quilometros": "quilometros",
    "quilometro": "quilometros",
    "km rodado": "quilometragem",
    "km rodados": "quilometragem",
    "distancia percorrida": "distancia",
    "valor arrecadado": "arrecadacao",
    "arrecadacao": "arrecadacao",
    "receita bruta": "receita",
    "receita total": "receita",
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


def preservar_texto(valor: Any) -> Optional[str]:
    if valor is None:
        return None

    try:
        if pd.isna(valor):
            return None
    except (TypeError, ValueError):
        pass

    return str(valor).strip()


def _normalizar_tipo_relatorio(nome: str) -> str:
    texto = normalizar_texto(nome).replace(" ", "_")
    texto = re.sub(r"_+", "_", texto)
    return texto.strip("_")


def _inferir_periodicidade(tipo_relatorio: str) -> Optional[str]:
    if any(item in tipo_relatorio for item in ("diario", "diaria", "diariamente")):
        return "diaria"

    if any(item in tipo_relatorio for item in ("semanal", "semana")):
        return "semanal"

    if any(item in tipo_relatorio for item in ("mensal", "mes")):
        return "mensal"

    return None


def extrair_metadados_nome_arquivo(nome_arquivo: str) -> Dict[str, Any]:
    nome_base = re.sub(
        r"\.html?$",
        "",
        nome_arquivo.strip(),
        flags=re.IGNORECASE
    )

    nome_tipo = re.sub(
        r"(?:[_-]?(?:\d{4})[_-]?(?:\d{2})[_-]?(?:\d{2})|"
        r"[_-](?:\d{4})[_-]?(?:s(?:emana)?[_-]?)?\d{1,2}|"
        r"[_-]?(?:\d{4})[_-]?(?:0[1-9]|1[0-2]))$",
        "",
        nome_base,
        flags=re.IGNORECASE
    )

    tipo_relatorio = _normalizar_tipo_relatorio(nome_tipo)
    periodicidade = _inferir_periodicidade(tipo_relatorio)

    metadados = {
        "tipo_relatorio": tipo_relatorio,
        "periodicidade": periodicidade,
        "ano": None,
        "mes": None,
        "semana": None,
        "data": None,
    }

    match_diario = re.search(
        r"(?:^|[_-])(\d{4})[_-]?(\d{2})[_-]?(\d{2})$",
        nome_base
    )

    if match_diario:
        try:
            data = datetime(
                int(match_diario.group(1)),
                int(match_diario.group(2)),
                int(match_diario.group(3)),
            )
        except ValueError:
            data = None

        if data is not None:
            metadados["periodicidade"] = "diaria"
            metadados["ano"] = data.year
            metadados["mes"] = data.month
            metadados["data"] = data.date().isoformat()
            return metadados

    if periodicidade == "semanal":
        match_semanal = re.search(
            r"(?:^|[_-])(\d{4})[_-]?(?:s(?:emana)?[_-]?)?(\d{1,2})$",
            nome_base,
            re.IGNORECASE
        )

        if match_semanal:
            ano = int(match_semanal.group(1))
            semana = int(match_semanal.group(2))

            if 1 <= semana <= 53:
                metadados["ano"] = ano
                metadados["semana"] = semana
                return metadados

    match_mensal = re.search(
        r"(?:^|[_-])(\d{4})[_-]?(0[1-9]|1[0-2])$",
        nome_base
    )

    if match_mensal:
        metadados["periodicidade"] = periodicidade or "mensal"
        metadados["ano"] = int(match_mensal.group(1))
        metadados["mes"] = int(match_mensal.group(2))
        return metadados

    return metadados


def _normalizar_parte_coluna(valor: Any) -> str:
    texto = normalizar_texto(valor)
    texto = re.sub(r"[^\w\s]", " ", texto)
    return re.sub(r"\s+", "_", texto).strip("_")


def normalizar_nome_coluna(coluna: Any) -> str:
    if isinstance(coluna, tuple):
        partes = []

        for item in coluna:
            parte = _normalizar_parte_coluna(item)

            if not parte or parte.startswith("unnamed"):
                continue

            tokens = [
                token
                for token in parte.split("_")
                if token not in CABECALHOS_GENERICOS
            ]

            parte = "_".join(tokens)

            if parte and parte not in partes:
                partes.append(parte)

        texto = "_".join(partes)
    else:
        texto = _normalizar_parte_coluna(coluna)

    texto = re.sub(r"_+", "_", texto).strip("_")

    if texto in ALIASES_COLUNAS:
        return ALIASES_COLUNAS[texto]

    for alias, canonico in sorted(
        ALIASES_COLUNAS.items(),
        key=lambda item: len(item[0]),
        reverse=True
    ):
        alias_normalizado = _normalizar_parte_coluna(alias)

        if texto.endswith(f"_{alias_normalizado}"):
            prefixo = texto[
                :-(len(alias_normalizado) + 1)
            ].strip("_")

            if not prefixo or prefixo in CABECALHOS_GENERICOS:
                return canonico

    tokens = texto.split("_") if texto else []

    if len(tokens) == 2 and tokens[0] == tokens[1]:
        texto = tokens[0]

    return texto


def desduplicar_colunas(colunas: List[str]) -> List[str]:
    vistas: Dict[str, int] = {}
    novas_colunas: List[str] = []

    for col in colunas:
        col_limpa = col.strip() if col else "coluna"

        if not col_limpa:
            col_limpa = "coluna"

        if col_limpa in vistas:
            vistas[col_limpa] += 1
            novas_colunas.append(f"{col_limpa}_{vistas[col_limpa]}")
        else:
            vistas[col_limpa] = 0
            novas_colunas.append(col_limpa)

    return novas_colunas


def nome_coluna_base(coluna: str) -> str:
    return re.sub(r"_\d+$", "", coluna)


def coluna_eh_texto_estrito(coluna: str) -> bool:
    return nome_coluna_base(coluna) in COLUNAS_TEXTO_ESTRITO


def coluna_eh_inteira(coluna: str) -> bool:
    return nome_coluna_base(coluna) in COLUNAS_INTEIRAS


def coluna_eh_numerica(coluna: str) -> bool:
    base = nome_coluna_base(coluna)

    if coluna_eh_texto_estrito(base):
        return False

    if base in COLUNAS_INTEIRAS or base in COLUNAS_NUMERICAS:
        return True

    tokens = set(base.split("_"))

    tokens_numericos = {
        "quilometragem", "quilometros", "km", "distancia", "viagens", "passageiros",
        "pagantes", "nao", "arrecadacao", "receita", "faturamento", "custo", "despesa",
        "tarifa", "valor", "percentual", "percentagem", "taxa", "quantidade", "qtd"
    }

    return bool(tokens.intersection(tokens_numericos))


def limpar_numero_brasileiro(valor: Any) -> Any:
    if valor is None:
        return None

    texto = str(valor).strip()
    texto_normalizado = normalizar_texto(texto)

    if not texto or texto_normalizado in {
        "", "nan", "none", "null", "na", "n_a", "-", "--"
    }:
        return None

    negativo = False

    if texto.startswith("(") and texto.endswith(")"):
        negativo = True
        texto = texto[1:-1].strip()

    texto = re.sub(
        r"^(r\$|rs\$|us\$)\s*",
        "",
        texto,
        flags=re.IGNORECASE
    )

    percentual = "%" in texto
    texto = texto.replace("%", "").replace("\xa0", " ")
    texto = re.sub(r"\s+", "", texto)

    if not texto or texto in {"-", "+"}:
        return None

    if "." in texto and "," in texto:
        texto = texto.replace(".", "").replace(",", ".")
    elif "," in texto:
        texto = texto.replace(",", ".")
    elif "." in texto:
        partes = texto.split(".")

        if (
            len(partes) > 1
            and all(parte.isdigit() for parte in partes)
            and len(partes[-1]) == 3
            and all(len(parte) == 3 for parte in partes[1:])
        ):
            texto = "".join(partes)

    if not re.fullmatch(r"\d+(?:\.\d+)?", texto):
        return None

    try:
        numero = float(texto)
    except ValueError:
        return None

    if negativo:
        numero = -numero

    if percentual:
        return numero

    return numero


def tentar_converter_coluna_numerica(
    serie: pd.Series,
    inteira: bool = False
) -> Optional[pd.Series]:
    serie_texto = serie.astype("string").str.strip()

    valores_convertidos = serie_texto.apply(
        limpar_numero_brasileiro
    )

    validos_originais = (
        serie_texto.notna()
        & (serie_texto != "")
    )

    if validos_originais.sum() == 0:
        return None

    taxa_sucesso = (
        valores_convertidos.notna()[validos_originais].mean()
    )

    if taxa_sucesso < 0.90:
        return None

    valores_numericos = pd.to_numeric(
        valores_convertidos,
        errors="coerce"
    )

    if inteira:
        validos = valores_numericos.dropna()

        if (
            not validos.empty
            and not ((validos % 1) == 0).all()
        ):
            return valores_numericos

        return valores_numericos.astype("Int64")

    return valores_numericos.astype("Float64")


def pontuar_tabela(df: pd.DataFrame) -> tuple:
    colunas_normalizadas = {
        normalizar_nome_coluna(col)
        for col in df.columns
    }

    colunas_reconhecidas = (
        colunas_normalizadas.intersection(
            COLUNAS_TRANSPORTE
        )
    )

    pontuacao = sum(
        PESOS_COLUNAS_TRANSPORTE.get(coluna, 1)
        for coluna in colunas_reconhecidas
    )

    return (
        pontuacao,
        len(colunas_reconhecidas),
        len(df),
        df.shape[0] * df.shape[1]
    )


def selecionar_tabela_principal(
    tabelas: List[pd.DataFrame]
) -> pd.DataFrame:
    tabelas_validas = [
        tabela
        for tabela in tabelas
        if tabela.shape[0] > 0
        and tabela.shape[1] > 0
    ]

    if not tabelas_validas:
        raise ValueError(
            "Nenhuma tabela com dados válidos encontrada."
        )

    return max(
        tabelas_validas,
        key=pontuar_tabela
    )


def _obter_indices_colunas_artificiais(
    df: pd.DataFrame
) -> List[str]:
    colunas_remover = []

    for coluna in df.columns:
        if re.fullmatch(
            r"unnamed(?:_\d+)?",
            nome_coluna_base(coluna),
            flags=re.IGNORECASE
        ):
            colunas_remover.append(coluna)

    return colunas_remover


def higienizar_dataframe(
    df: pd.DataFrame,
    metadados: Dict[str, Any]
) -> pd.DataFrame:
    df = df.copy()

    colunas_processadas = [
        normalizar_nome_coluna(coluna)
        for coluna in df.columns
    ]

    df.columns = desduplicar_colunas(
        colunas_processadas
    )

    colunas_artificiais = (
        _obter_indices_colunas_artificiais(df)
    )

    if colunas_artificiais:
        df = df.drop(
            columns=colunas_artificiais
        )

    df = (
        df
        .dropna(how="all")
        .dropna(axis=1, how="all")
        .copy()
    )

    if df.empty:
        return df

    termos_ignorar = re.compile(
        r"^(total|subtotal|resumo|media|fonte:|emissao:|pagina:)",
        re.IGNORECASE,
    )

    mascara_ignorar = pd.Series(
        False,
        index=df.index,
        dtype=bool,
    )

    linha_cabecalho_repetida = pd.Series(
        True,
        index=df.index,
        dtype=bool,
    )

    for col in df.columns[:3]:
        texto = (
            df[col]
            .astype("string")
            .fillna("")
            .map(normalizar_texto)
        )

        mascara_ignorar |= texto.str.match(
            termos_ignorar,
            na=False
        )

        linha_cabecalho_repetida &= (
            texto == normalizar_texto(col)
        )

    if len(df.columns) < 3:
        linha_cabecalho_repetida = pd.Series(
            False,
            index=df.index,
            dtype=bool,
        )

        for col in df.columns:
            texto = (
                df[col]
                .astype("string")
                .fillna("")
                .map(normalizar_texto)
            )

            linha_cabecalho_repetida |= (
                texto == normalizar_texto(col)
            )

    mascara_ignorar |= linha_cabecalho_repetida

    df = df.loc[
        ~mascara_ignorar
    ].copy()

    for col in df.columns:
        if coluna_eh_texto_estrito(col):
            df[col] = (
                df[col]
                .astype("string")
                .str.strip()
            )
            continue

        serie = (
            df[col]
            .astype("string")
            .str.strip()
        )

        if coluna_eh_numerica(col):
            serie_num = tentar_converter_coluna_numerica(
                serie,
                inteira=coluna_eh_inteira(col),
            )

            df[col] = (
                serie_num
                if serie_num is not None
                else serie
            )
        else:
            df[col] = serie

    df["meta_tipo_relatorio"] = (
        metadados["tipo_relatorio"]
    )

    df["meta_periodicidade"] = (
        metadados["periodicidade"]
    )

    if metadados["ano"] is not None:
        df["meta_ano"] = metadados["ano"]

    if metadados["mes"] is not None:
        df["meta_mes"] = metadados["mes"]

    if metadados["semana"] is not None:
        df["meta_semana"] = metadados["semana"]

    if metadados["data"] is not None:
        df["meta_data"] = metadados["data"]

    return df


def _obter_converters(
    tabelas: List[pd.DataFrame]
) -> Dict[Any, Any]:
    converters: Dict[Any, Any] = {}

    for tabela in tabelas:
        for coluna in tabela.columns:
            converters[coluna] = preservar_texto

            if isinstance(coluna, tuple):
                for sub_coluna in coluna:
                    converters[sub_coluna] = preservar_texto

    return converters


def processar_html_bytes(
    conteudo_bytes: bytes,
    nome_arquivo: str
) -> Dict[str, Any]:
    erros = []
    tabelas = None

    for encoding in (
        "utf-8",
        "cp1252",
        "latin-1"
    ):
        try:
            tabelas_previa = pd.read_html(
                io.BytesIO(conteudo_bytes),
                encoding=encoding,
                decimal=".",
                thousands=None,
                keep_default_na=True,
            )

            if not tabelas_previa:
                continue

            converters = _obter_converters(
                tabelas_previa
            )

            tabelas = pd.read_html(
                io.BytesIO(conteudo_bytes),
                encoding=encoding,
                decimal=".",
                thousands=None,
                converters=converters,
                keep_default_na=True,
            )

            if tabelas:
                break

        except (
            ValueError,
            UnicodeDecodeError
        ) as exc:
            erros.append(
                f"{encoding}: {exc}"
            )

    if not tabelas:
        detalhe = " | ".join(erros)

        raise ValueError(
            f"Não foi possível interpretar o HTML: {detalhe}"
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
            metadados
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
        "total_registros_validos": len(dados_finais),
        "colunas": list(
            df_processado.columns
        ),
        "dados": dados_finais,
    }
