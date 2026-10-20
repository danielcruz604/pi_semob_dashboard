from app.utils.connection_factory import ConnectionFactory

class UsuarioDAO:
    def __init__(self):
        # Pega a instância única do banco
        self.db = ConnectionFactory().db
        self.collection = self.db["usuarios"]

    def buscar_por_email(self, email: str) -> dict:
        return self.collection.find_one({"email": email})

    def inserir(self, usuario_dict: dict) -> str:
        resultado = self.collection.insert_one(usuario_dict)
        return str(resultado.inserted_id)
