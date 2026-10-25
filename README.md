# SEMOB Dashboard

Dashboard de operação do transporte coletivo de **São Caetano do Sul**, desenvolvido em parceria com a **Secretaria de Mobilidade Urbana (SEMOB-SCS)** como Projeto Integrador da disciplina **TTI206 – Desenvolvimento Multiplataformas** do **Instituto Mauá de Tecnologia** (2026/2).

## Sobre

Os dados operacionais da frota chegam à SEMOB por e-mail, em relatórios HTML avulsos. Hoje, o tratamento desses dados e a geração de indicadores são feitos manualmente.

O SEMOB Dashboard automatiza esse processo:

- O analista entra com login autenticado e envia os relatórios `.html` pela aplicação.
- O backend extrai, limpa e consolida os dados no MongoDB.
- O frontend exibe painéis com quilometragem, viagens, horários, passageiros e indicadores financeiros.

## Tecnologias

- **Frontend:** Flutter (Dart), com versões Web, Desktop e Mobile
- **Backend:** Python, FastAPI e autenticação JWT
- **Banco de dados:** MongoDB
- **Testes:** Pytest (backend) e flutter_test (frontend)

## Estrutura

```
pi_semob_dashboard/
├── backend/
│   ├── app/            # Rotas, serviços, schemas e testes da API
│   ├── scripts/        # Scripts auxiliares (ex.: usuários de demonstração)
│   └── main.py         # Ponto de entrada da API
└── frontend/flutter/   # Aplicação Flutter
```

## Como executar

### Pré-requisitos
- Python 3.11 ou 3.12
- MongoDB (local ou Atlas)
- Flutter SDK 3.38+ (Dart 3.10+)

### 1. Backend

```bash
cd backend
python -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate
pip install -r requirements.txt
```

Crie o arquivo `backend/.env`:

```env
MONGO_URI=mongodb://localhost:27017
DATABASE_NAME=semob_dashboard
JWT_SECRET=troque-por-uma-chave-segura
JWT_EXPIRE_MINUTES=480
```

Cadastre os usuários de demonstração (só é preciso fazer uma vez):

```bash
python -m scripts.criar_usuarios_demo
```

Inicie o servidor:

```bash
uvicorn main:app --reload
```

A API fica disponível em http://localhost:8000. A documentação interativa (Swagger) está em http://localhost:8000/docs.

### 2. Frontend

Com o backend rodando:

```bash
cd frontend/flutter
flutter pub get
flutter run -d chrome            # ou windows, macos, linux, ou um dispositivo Android/iOS
```

Por padrão, o app acessa a API em `http://localhost:8000`. No emulador Android, o endereço usado é `http://10.0.2.2:8000`. Para apontar para outro servidor, use:

```bash
flutter run -d chrome --dart-define=API_BASE_URL=http://seu-servidor:8000
```

### Acesso de demonstração

| Perfil | E-mail | Senha |
|---|---|---|
| Gestor | gestor@semob.sp.gov.br | semob2026 |
| Analista | analista@semob.sp.gov.br | transporte123 |
| Fiscal | fiscal@semob.sp.gov.br | fiscal2026 |

### Testes

```bash
# Backend
cd backend
pytest

# Frontend
cd frontend/flutter
flutter test
```

## Equipe

- Daniel Cruz Santana
- Guilherme Zanelli de Novaes
- Lindsay Luna Sanchez Jaldin
- Lucas Quadros das Dores

**Parceiro:** SEMOB – Prefeitura de São Caetano do Sul
**Instituição:** Instituto Mauá de Tecnologia

## Licença

[MIT](LICENSE)
