import os
from pathlib import Path
import threading
from typing import Optional
from dotenv import load_dotenv
from pymongo import MongoClient
from pymongo.database import Database

BASE_DIR = Path(__file__).resolve().parent.parent.parent
load_dotenv(dotenv_path=BASE_DIR / ".env")

class ConnectionFactory:
    _instance: Optional["ConnectionFactory"] = None
    _lock = threading.Lock()

    def __new__(cls):
        if cls._instance is None:
            with cls._lock:
                if cls._instance is None:
                    instancia = super().__new__(cls)
                    instancia._client = None
                    instancia._db = None
                    cls._instance = instancia
        return cls._instance

    @property
    def db(self) -> Database:
        if self._db is None:
            with self._lock:
                if self._db is None:
                    uri = os.getenv("MONGO_URI")
                    nome_db = os.getenv("DATABASE_NAME")
                    if not uri or not nome_db:
                        raise RuntimeError("As variáveis MONGO_URI e DATABASE_NAME são obrigatórias.")
                    self._client = MongoClient(uri, serverSelectionTimeoutMS=5000)
                    self._db = self._client[nome_db]
        return self._db

    def close(self) -> None:
        with self._lock:
            if self._client is not None:
                self._client.close()
            self._client = None
            self._db = None
