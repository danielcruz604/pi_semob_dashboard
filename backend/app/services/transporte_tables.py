import io
import re
import warnings
from typing import Any, Callable, Dict, List, Optional
import pandas as pd

TABLE_RE = re.compile(rb"<table\b([^>]*)>(.*?)</table\s*>", re.IGNORECASE | re.DOTALL)
HEADER_FIX_RE = re.compile(
    rb"(<table\b[^>]*>\s*)((?:<th\b.*?</th\s*>\s*)+)",
    re.IGNORECASE | re.DOTALL,
)
CELULA_RE = re.compile(rb"<t[hd]\b", re.IGNORECASE)
TR_SPLIT_RE = re.compile(rb"<tr\b", re.IGNORECASE)

def preservar_texto(valor: Any) -> Optional[str]:
    if valor is None:
        return None
    try:
        if pd.isna(valor):
            return None
    except (TypeError, ValueError):
        pass
    texto = str(valor).strip()
    return texto if texto else None

def _classes_tabela(atributos: bytes) -> set:
    padrao = rb"(?<![\w-])class\s*="
    match = re.search(padrao + rb"\s*(['\"])(.*?)\1", atributos, re.IGNORECASE | re.DOTALL)
    if match:
        return set(match.group(2).decode("latin-1", "replace").lower().split())
    match = re.search(padrao + rb"\s*([^\s>]+)", atributos, re.IGNORECASE)
    if match:
        return set(match.group(1).decode("latin-1", "replace").strip("'\"").lower().split())
    return set()

def _detectar_encoding(conteudo_bytes: bytes) -> List[str]:
    cabecalho = conteudo_bytes[:8192]
    match = re.search(rb"charset\s*=\s*['\"]?\s*([\w.-]+)", cabecalho, re.IGNORECASE)
    candidatos: List[str] = []
    if match:
        declarado = match.group(1).decode("ascii", "ignore").lower()
        aliases = {
            "cp1252": "cp1252", "windows-1252": "cp1252",
            "latin1": "latin-1", "iso-8859-1": "latin-1", "utf8": "utf-8",
        }
        declarado = aliases.get(declarado, declarado)
        if declarado in {"utf-8", "cp1252", "latin-1"}:
            candidatos.append(declarado)
    for encoding in ("utf-8", "cp1252", "latin-1"):
        if encoding not in candidatos:
            candidatos.append(encoding)
    return candidatos

def _reparar_cabecalho_tabela(fragmento: bytes) -> bytes:
    #Envolve <th> soltos logo após <table> em um <tr> (idempotente).
    corrigido, _ = HEADER_FIX_RE.subn(
        lambda m: m.group(1) + b"<tr>" + m.group(2) + b"</tr>",
        fragmento,
        count=1,
    )
    return corrigido

def _numero_colunas_cabecalho(fragmento: bytes) -> int:
    primeiro_tr = re.search(rb"<tr\b[^>]*>(.*?)</tr\s*>", fragmento, re.IGNORECASE | re.DOTALL)
    if primeiro_tr:
        numero = len(re.findall(rb"<th\b", primeiro_tr.group(1), re.IGNORECASE))
        if numero:
            return numero
    return len(re.findall(rb"<th\b", fragmento, re.IGNORECASE))

def _numero_colunas_maximo(fragmento: bytes) -> int:
    #Maior número de células (<th>/<td>) em qualquer linha; não exige </tr>.
    linhas = TR_SPLIT_RE.split(fragmento)[1:]
    maximo = max((len(CELULA_RE.findall(linha)) for linha in linhas), default=0)
    return max(maximo, _numero_colunas_cabecalho(fragmento))

def _parsear_tabela(fragmento: bytes, encoding: str) -> pd.DataFrame:
    #Decodificação estrita: UnicodeDecodeError aciona o próximo encoding.
    html = fragmento.decode(encoding)
    conversores: Dict[Any, Callable[[Any], Optional[str]]] = {
        indice: preservar_texto for indice in range(_numero_colunas_maximo(fragmento))
    }
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        tabelas = pd.read_html(
            io.StringIO(html),
            decimal=".",
            thousands=None,
            converters=conversores,
            keep_default_na=False,
        )
    if not tabelas:
        raise ValueError("A tabela HTML não contém dados legíveis.")
    return tabelas[0]

def ler_tabelas_html(conteudo_bytes: bytes) -> List[pd.DataFrame]:
    if not conteudo_bytes:
        raise ValueError("O arquivo HTML está vazio.")

    fragmentos: List[bytes] = []
    for match in TABLE_RE.finditer(conteudo_bytes):
        if "data" not in _classes_tabela(match.group(1)):
            continue
        fragmento = _reparar_cabecalho_tabela(match.group(0))
        if _numero_colunas_cabecalho(fragmento) < 3:
            continue
        fragmentos.append(fragmento)

    if not fragmentos:
        raise ValueError("Nenhuma tabela operacional encontrada no HTML.")

    erros: List[str] = []
    for encoding in _detectar_encoding(conteudo_bytes):
        try:
            return [_parsear_tabela(f, encoding) for f in fragmentos]
        except (ValueError, ImportError, IndexError) as exc:  # UnicodeDecodeError ⊂ ValueError
            erros.append(f"{encoding}: {exc}")

    raise ValueError(
        "Não foi possível interpretar as tabelas operacionais do HTML. " + " | ".join(erros)
    )