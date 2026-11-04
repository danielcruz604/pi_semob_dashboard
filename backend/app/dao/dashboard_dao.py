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

    def obter_linhas_unicas(self, colecao: str) -> List[Dict[str, Any]]:
        return list(self.db[colecao].find({}, {"linha": 1, "_id": 0}))

    def agregar_resumo_viagens(self, filtro: Dict[str, Any], por_linha: bool = False) -> Dict[str, Any]:
            colecao = COL_VIAGENS_LINHAS if por_linha else COL_VIAGENS_SISTEMA
            
            pipeline = [
                {"$match": filtro},
                {"$group": {
                    "_id": None,
                    "km_total": {"$sum": "$kmTotal"},
                    "km_produtivo": {"$sum": "$kmProdTotal"},
                    "km_improdutivo": {"$sum": "$kmImprodTotal"},
                    "viagens_programadas": {"$sum": "$nrViagensProg"},
                    "viagens_realizadas": {"$sum": "$nrTotalViagensRealizadas"},
                    "viagens_linha": {"$sum": "$nrViagens"} # Fallback seguro
                }}
            ]
            
            dias_unicos = len(self.db[colecao].distinct("data", filtro))
            
            resultado = list(self.db[colecao].aggregate(pipeline))
            if resultado:
                doc = resultado[0]
                doc["dias_com_km"] = dias_unicos
                return doc
            return {}

    def agregar_resumo_passageiros(self, filtro: Dict[str, Any]) -> Dict[str, Any]:
        """Soma os dados de bilhetagem no banco."""
        pipeline = [
            {"$match": filtro},
            {"$group": {
                "_id": None,
                "catraca": {"$sum": "$catraca"},
                "antecipados": {"$sum": "$antecipados"},
                "nao_pagantes": {"$sum": "$naoPagantes"},
                "total_geral": {"$sum": "$totalPassageiros"}
            }}
        ]
        resultado = list(self.db[COL_PASSAGEIROS_SISTEMA].aggregate(pipeline))
        return resultado[0] if resultado else {}

