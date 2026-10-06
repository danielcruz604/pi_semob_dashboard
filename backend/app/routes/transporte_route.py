from fastapi import APIRouter, File, HTTPException, UploadFile
from app.schemas.transporte_schema import RespostaProcessamentoSchema
from app.services.transporte_service import processar_html_bytes

router = APIRouter(prefix="/transporte", tags=["Transporte"])

MAX_UPLOAD_BYTES = 20 * 1024 * 1024
CHUNK_SIZE = 1024 * 1024

@router.post("/processar-html", response_model=RespostaProcessamentoSchema)
def processar_html(file: UploadFile = File(...)):
    if not file.filename:
        raise HTTPException(status_code=400, detail="Nome de arquivo não informado.")

    nome_arquivo = file.filename.strip()
    if not nome_arquivo.lower().endswith((".html", ".htm")):
        raise HTTPException(status_code=400, detail="Envie um arquivo .html ou .htm.")

    conteudo_buffer = bytearray()
    while chunk := file.file.read(CHUNK_SIZE):
        conteudo_buffer.extend(chunk)
        if len(conteudo_buffer) > MAX_UPLOAD_BYTES:
            raise HTTPException(
                status_code=413,
                detail=f"Arquivo excede o limite máximo de {MAX_UPLOAD_BYTES // (1024 * 1024)} MB."
            )

    conteudo_bytes = bytes(conteudo_buffer)
    if not conteudo_bytes:
        raise HTTPException(status_code=400, detail="O arquivo enviado está vazio.")

    try:
        resultado = processar_html_bytes(conteudo_bytes, nome_arquivo)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc

    return resultado