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
            client = MongoClient(os.getenv("MONGO_URI"))
            cls._instance._db = client[os.getenv("DATABASE_NAME")]
        return cls._instance

    @property
    def db(self):
        return self._db