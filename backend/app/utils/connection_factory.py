import os
from pymongo import MongoClient
from dotenv import load_dotenv

load_dotenv()

class ConnectionFactory:
    _instance = None
    _db = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super(ConnectionFactory, cls).__new__(cls)

            uri = os.getenv("MONGO_URI", "mongodb://localhost:27017/")
            db_name = os.getenv("DATABASE_NAME", "semob_db")

            client = MongoClient(uri)
            cls._instance._db = client[db_name]
        return cls._instance

    @property
    def db(self):
        return self._db