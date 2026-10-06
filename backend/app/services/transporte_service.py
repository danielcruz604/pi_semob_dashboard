import io
import json
import re
import unicodedata
from typing import Any, Dict, List, Optional
import pandas as pd

COLUNAS_TEXTO_ESTRITO = {
    "linha", "cod_linha", "codigo_linha", "prefixo", "servico",
    "empresa", "consorcio", "itinerario", "sentido", "faixa_horaria"
}

COLUNAS_TRANSPORTE = {
    "linha", "cod_linha", "codigo_linha", "prefixo", "servico",
    "empresa", "consorcio", "itinerario", "sentido", "faixa_horaria",
    "horario", "data", "passageiros", "viagens"
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
    """Preserva o valor lido do HTML como texto, sem inferência numérica."""
    if valor is None:
        return None

    try:
        if pd.isna(valor):
            return None
    except (TypeError, ValueError):
        pass

    return str(valor).strip()


def extrair_metadados_nome_arquivo(nome_arquivo: str) -> Dict[str, Any]:
    nome_base = re.sub(r"\.html?$", "", nome_arquivo.strip(), flags=re.IGNORECASE)

    padrao = re.compile(r"^(.+?)_?(\d{4})(0[1-9]|1[0-2])$")
    match = padrao.match(nome_base)

    if not match:
        return {
            "tipo_relatorio": normalizar_texto(nome_base).replace(" ", "_"),
            "ano": None,
            "mes": None,
        }

    tipo, ano, mes = match.groups()
    return {
        "tipo_relatorio": normalizar_texto(tipo).replace(" ", "_"),
        "ano": int(ano),
        "mes": int(mes),
    }


def normalizar_nome_coluna(coluna: Any) -> str:
    if isinstance(coluna, tuple):
        partes = [str(item) for item in coluna if "Unnamed" not in str(item)]
        texto = " ".join(partes)
    else:
        texto = str(coluna)

    texto = unicodedata.normalize("NFKD", texto).encode("ASCII", "ignore").decode("utf-8").lower()
    texto = re.sub(r"[^\w\s]", " ", texto)
    return re.sub(r"\s+", "_", texto).strip("_")


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
    """Somente nomes conhecidos são mantidos obrigatoriamente como texto."""
    return nome_coluna_base(coluna) in COLUNAS_TEXTO_ESTRITO


def limpar_numero_brasileiro(valor: Any) -> Any:
    if valor is None:
        return None

    texto = str(valor).strip()

    if not texto or normalizar_texto(texto) in {"", "nan", "none", "null", "-", "--"}:
        return None

    texto = texto.replace("%", "").replace("\xa0", " ")
    texto = re.sub(r"\s+", "", texto)

    if not texto or texto in {"-", "+"}:
        return None

    if "." in texto and "," in texto:
        # Ex.: 1.234,56 -> 1234.56
        texto = texto.replace(".", "").replace(",", ".")
    elif "," in texto:
        # Ex.: 12,50 -> 12.50
        texto = texto.replace(",", ".")
    elif "." in texto:
        partes = texto.split(".")

        # Mantém pontos decimais como 12.5 e 12.50.
        # Remove apenas pontos que tenham claramente função de milhar.
        if (
            len(partes) > 1
            and all(p.isdigit() for p in partes)
            and len(partes[-1]) == 3
            and 1 <= len(partes[0]) <= 3
        ):
            texto = "".join(partes)

    if not re.fullmatch(r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)", texto):
        return None

    try:
        return float(texto)
    except ValueError:
        return None


def tentar_converter_coluna_numerica(serie: pd.Series) -> Optional[pd.Series]:
    serie_texto = serie.astype("string").str.strip()
    amostra = serie_texto.dropna().head(50)

    if amostra.empty:
        return None

    padrao = re.compile(
        r"^[+-]?(?:\d+(?:[.,]\d+)?|\d{1,3}(?:\.\d{3})+(?:,\d+)?)%?$"
    )

    candidatos = amostra.apply(
        lambda v: bool(padrao.match(str(v).replace(" ", "")))
    )

    if float(candidatos.mean()) < 0.70:
        return None

    valores_convertidos = serie_texto.apply(limpar_numero_brasileiro)
    validos_originais = serie_texto.notna()

    if validos_originais.sum() > 0:
        taxa_sucesso = valores_convertidos.notna()[validos_originais].mean()

        if taxa_sucesso < 0.90:
            return None

    return pd.to_numeric(valores_convertidos, errors="coerce")


def pontuar_tabela(df: pd.DataFrame) -> tuple:
    colunas_normalizadas = {normalizar_nome_coluna(col) for col in df.columns}
    correspondencias = len(colunas_normalizadas.intersection(COLUNAS_TRANSPORTE))
    return (correspondencias, len(df), df.shape[0] * df.shape[1])


def selecionar_tabela_principal(tabelas: List[pd.DataFrame]) -> pd.DataFrame:
    tabelas_validas = [t for t in tabelas if t.shape[0] > 0 and t.shape[1] > 0]

    if not tabelas_validas:
        raise ValueError("Nenhuma tabela com dados válidos encontrada.")

    return max(tabelas_validas, key=pontuar_tabela)


def higienizar_dataframe(df: pd.DataFrame, metadados: Dict[str, Any]) -> pd.DataFrame:
    df = df.copy()

    colunas_processadas = [normalizar_nome_coluna(c) for c in df.columns]
    df.columns = desduplicar_colunas(colunas_processadas)

    df = df.dropna(how="all").dropna(axis=1, how="all").copy()

    if df.empty:
        return df

    termos_ignorar = re.compile(
        r"^(total|subtotal|resumo|media|fonte:|emissao:|pagina:)",
        re.IGNORECASE,
    )

    mascara_ignorar = pd.Series(False, index=df.index, dtype=bool)
    linha_cabecalho_repetida = pd.Series(True, index=df.index, dtype=bool)

    for col in df.columns[:3]:
        texto = df[col].astype("string").fillna("").map(normalizar_texto)
        mascara_ignorar |= texto.str.match(termos_ignorar, na=False)
        linha_cabecalho_repetida &= texto == normalizar_texto(col)

    mascara_ignorar |= linha_cabecalho_repetida
    df = df.loc[~mascara_ignorar].copy()

    for col in df.columns:
        if coluna_eh_texto_estrito(col):
            df[col] = df[col].astype("string").str.strip()
            continue

        serie = df[col].astype("string").str.strip()
        serie_num = tentar_converter_coluna_numerica(serie)
        df[col] = serie_num if serie_num is not None else serie

    df["meta_tipo_relatorio"] = metadados["tipo_relatorio"]

    if metadados["ano"] is not None:
        df["meta_ano"] = metadados["ano"]
        df["meta_mes"] = metadados["mes"]

    return df


def _obter_converters(tabelas: List[pd.DataFrame]) -> Dict[str, Any]:
    """
    Monta converters para todos os cabeçalhos encontrados na primeira leitura.

    A primeira leitura serve apenas para descobrir os cabeçalhos. A segunda
    leitura usa esses converters e NÃO usa decimal/thousands, preservando os
    valores originais como texto antes da nossa própria conversão.
    """
    converters: Dict[str, Any] = {}

    for tabela in tabelas:
        for coluna in tabela.columns:
            converters[str(coluna)] = preservar_texto

            if isinstance(coluna, tuple):
                for sub_coluna in coluna:
                    converters[str(sub_coluna)] = preservar_texto

    return converters


def processar_html_bytes(conteudo_bytes: bytes, nome_arquivo: str) -> Dict[str, Any]:
    erros = []
    tabelas = None

    for encoding in ("utf-8", "cp1252", "latin-1"):
        try:
            # Primeira leitura: somente para descobrir as tabelas e seus cabeçalhos.
            tabelas_previa = pd.read_html(
                io.BytesIO(conteudo_bytes),
                encoding=encoding,
                decimal=".",
                thousands=None,
                keep_default_na=True,
            )

            if not tabelas_previa:
                continue

            converters = _obter_converters(tabelas_previa)

            # Segunda leitura: preserva todos os valores como texto.
            # Importante: NÃO usar decimal="," nem thousands="." aqui.
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

        except (ValueError, UnicodeDecodeError) as exc:
            erros.append(f"{encoding}: {exc}")

    if not tabelas:
        raise ValueError(
            f"Não foi possível interpretar o HTML: {' | '.join(erros)}"
        )

    metadados = extrair_metadados_nome_arquivo(nome_arquivo)
    df_bruto = selecionar_tabela_principal(tabelas)
    df_processado = higienizar_dataframe(df_bruto, metadados)

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
        "colunas": list(df_processado.columns),
        "dados": dados_finais,
    }
