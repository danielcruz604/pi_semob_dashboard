import logging
from typing import Tuple
from fastapi import APIRouter, File, HTTPException, UploadFile
from pymongo.errors import PyMongoError
from app.schemas.transporte_schema import (
    RespostaProcessamentoEPersistenciaSchema,
    RespostaProcessamentoSchema,
)
from app.services.transporte_service import (
    processar_e_persistir_html_bytes,
    processar_html_bytes,
)

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/transporte", tags=["Transporte"])

MAX_UPLOAD_BYTES = 20 * 1024 * 1024
CHUNK_SIZE = 1024 * 1024

def _ler_upload_html(file: UploadFile) -> Tuple[bytes, str]:
    try:
        if not file.filename:
            raise HTTPException(status_code=400, detail="Nome de arquivo não informado.")
        nome = file.filename.strip()
        if not nome.lower().endswith((".html", ".htm")):
            raise HTTPException(status_code=400, detail="Envie um arquivo .html ou .htm.")

        limite_mb = MAX_UPLOAD_BYTES // (1024 * 1024)
        if file.size is not None and file.size > MAX_UPLOAD_BYTES:
            raise HTTPException(status_code=413, detail=f"Arquivo excede o limite máximo de {limite_mb} MB.")

        buffer = bytearray()
        while chunk := file.file.read(CHUNK_SIZE):
            buffer.extend(chunk)
            if len(buffer) > MAX_UPLOAD_BYTES:
                raise HTTPException(status_code=413, detail=f"Arquivo excede o limite máximo de {limite_mb} MB.")
        if not buffer:
            raise HTTPException(status_code=400, detail="O arquivo enviado está vazio.")
        return bytes(buffer), nome
    finally:
        file.file.close()

@router.post("/processar-html", response_model=RespostaProcessamentoSchema)
def processar_html(file: UploadFile = File(...)):
    conteudo, nome = _ler_upload_html(file)
    try:
        return processar_html_bytes(conteudo, nome)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc

@router.post("/processar-e-salvar", response_model=RespostaProcessamentoEPersistenciaSchema)
def processar_e_salvar_html(file: UploadFile = File(...)):
    conteudo, nome = _ler_upload_html(file)
    try:
        return processar_e_persistir_html_bytes(conteudo, nome)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except RuntimeError as exc:
        logger.exception("Erro de configuração do banco")
        raise HTTPException(status_code=503, detail="Banco de dados não configurado.") from exc
    except PyMongoError as exc:
        logger.exception("Falha ao persistir no MongoDB")
        raise HTTPException(status_code=503, detail="Falha ao acessar o banco de dados.") from exc