from typing import Any, Dict, List
from pymongo.database import Database
from app.services.transporte_repository import (
    COL_FINANCEIRO_SISTEMA,
    COL_PASSAGEIROS_SISTEMA,
    COL_VIAGENS_HORARIO,
    COL_VIAGENS_LINHAS,
    COL_VIAGENS_OCORRENCIAS,
    COL_VIAGENS_SISTEMA,
)

class DashboardDAO:
    def __init__(self, db: Database):
        self.db = db

    def obter_datas_unicas(self, colecao: str) -> List[Dict[str, Any]]:
        return list(self.db[colecao].find({}, {"data": 1, "_id": 0}))
