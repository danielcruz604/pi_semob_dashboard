# SEMOB Dashboard

Dashboard de operação do transporte coletivo de São Caetano do Sul, desenvolvido em parceria com a Secretaria de Mobilidade Urbana (SEMOB-SCS) como Projeto Integrador da disciplina TTI206 – Desenvolvimento Multiplataformas, do Instituto Mauá de Tecnologia (2026/2).

## Sobre o projeto

Os dados operacionais da frota chegam à SEMOB por e-mail, em relatórios HTML avulsos gerados pelo sistema da concessionária. Hoje, a consolidação desses dados e a produção de indicadores são feitas manualmente, o que é lento e sujeito a erros.

O SEMOB Dashboard automatiza esse fluxo:

1. O analista entra no sistema com login e envia os relatórios `.html`.
2. O backend extrai as tabelas, limpa e padroniza os dados e os grava no MongoDB, sem duplicar registros quando um relatório é reenviado.
3. O aplicativo exibe indicadores, gráficos e alertas, com filtros por período e por linha.

## Funcionalidades

- **Ingestão de relatórios:** upload de um ou vários arquivos HTML do Smart Report (resumo mensal, FCV, linhas, faixas horárias, viagens não realizadas e não terminadas, passageiros e saldos), com validação de formato e tamanho.
- **Persistência idempotente:** índices únicos no MongoDB garantem que reprocessar um relatório não gera duplicatas.
- **Indicadores operacionais:** quilometragem, viagens programadas e realizadas, FCV por período (manhã, tarde e noite), frota, passageiros pagantes e gratuitos, dados financeiros e receita por quilômetro.
- **Análises:** série temporal diária, semanal e mensal, ranking de linhas, quadro de horários e comparação entre dias da semana.
- **Detecção de anomalias:** dias com quilometragem fora da média (desvio padrão e tolerância configurável, padrão de 15%), FCV abaixo da meta de 98% e quilometragem improdutiva acima de 10%.
- **Autenticação:** login com JWT, senhas armazenadas com hash bcrypt e sessão que pode ser mantida no dispositivo.

## Arquitetura

O sistema é dividido em três camadas:

| Camada | Tecnologia | Responsabilidade |
|---|---|---|
| Interface | Flutter (Dart) | Aplicativo multiplataforma (web, desktop e mobile) com login, upload e dashboard |
| API e ETL | Python, FastAPI | Extração e tratamento dos relatórios, regras de negócio, autenticação e endpoints do dashboard |
| Persistência | MongoDB | Armazenamento dos dados operacionais, financeiros e de usuários |

Principais bibliotecas:

- **Backend:** FastAPI, Uvicorn, Pydantic, PyMongo, Pandas, BeautifulSoup, lxml, bcrypt, PyJWT e python-dotenv.
- **Frontend:** http, fl_chart, file_picker, shared_preferences e intl.
- **Testes:** Pytest, HTTPX, mongomock e flutter_test.

## Estrutura do repositório

```
pi_semob_dashboard/
├── backend/
│   ├── main.py                 # Inicialização da API (CORS, rotas e índices do banco)
│   ├── requirements.txt
│   ├── scripts/                # Scripts auxiliares (cadastro das contas de demonstração)
│   └── app/
│       ├── routes/             # Endpoints: usuários, transporte (ingestão) e dashboard
│       ├── services/           # Pipeline de ETL, consultas do dashboard e autenticação
│       ├── schemas/            # Contratos Pydantic das coleções e das respostas da API
│       ├── dao/                # Acesso à coleção de usuários
│       ├── utils/              # Conexão com o MongoDB e configuração do JWT
│       └── tests/              # Testes unitários e de integração
└── frontend/
    └── flutter/
        ├── lib/                # Telas, serviços de API e de sessão
        └── test/               # Testes automatizados do aplicativo
```

## Como executar

### Pré-requisitos

- Python 3.11 ou superior (recomendado 3.12)
- MongoDB (local ou Atlas)
- Flutter SDK 3.38 ou superior (Dart 3.10)

### Backend

```bash
cd backend
python -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate
pip install -r requirements.txt
```

Crie o arquivo `backend/.env` com as variáveis abaixo. Esse arquivo é ignorado pelo Git e nunca deve ser commitado.

| Variável | Descrição |
|---|---|
| `MONGO_URI` | String de conexão do MongoDB |
| `DATABASE_NAME` | Nome do banco de dados |
| `JWT_SECRET` | Chave usada para assinar os tokens de login |
| `JWT_EXPIRE_MINUTES` | Validade do login, em minutos (opcional, padrão 480) |

Cadastre as contas de demonstração (necessário apenas uma vez por banco):

```bash
python -m scripts.criar_usuarios_demo
```

Inicie a API:

```bash
uvicorn main:app --reload
```

A API fica disponível em `http://localhost:8000`, e a documentação interativa (Swagger) em `http://localhost:8000/docs`.

### Frontend

Com a API em execução:

```bash
cd frontend/flutter
flutter pub get
flutter run -d chrome            # ou windows, macos, linux, ou um dispositivo Android/iOS
```

O aplicativo acessa a API em `http://localhost:8000` por padrão (no emulador Android, `http://10.0.2.2:8000`). Para usar outro endereço:

```bash
flutter run -d chrome --dart-define=API_BASE_URL=http://endereco-da-api:8000
```

As credenciais das contas de demonstração (perfis gestor, analista e fiscal) são repassadas pela equipe.

## Testes

Os testes do backend usam um MongoDB em memória e não precisam do arquivo `.env` nem de um banco em execução. Os testes do frontend simulam as respostas da API.

```bash
# Backend
cd backend
pytest

# Frontend
cd frontend/flutter
flutter test
```

## API

Todas as rotas usam o prefixo `/api`. A lista completa, com os parâmetros e os formatos de resposta, está no Swagger (`/docs`).

| Grupo | Rotas principais |
|---|---|
| Usuários | `POST /usuarios/login`, `GET /usuarios/perfil` |
| Transporte | `POST /transporte/processar-html`, `POST /transporte/processar-e-salvar` |
| Dashboard | `GET /dashboard/resumo-operacional`, `/serie-temporal`, `/linhas-ranking`, `/horarios`, `/anomalias`, `/relatorio` |

## Fluxo de trabalho

- **Branches:** `<área>_<nome>` (por exemplo, `Backend_Zanelli` e `Frontend_Lindsay`), com integração por Pull Request.
- **Commits:** padrão [Conventional Commits](https://www.conventionalcommits.org/pt-br/), como `feat(backend): ...` e `fix(frontend): ...`.
- **Tarefas:** quadro Kanban no GitHub Projects, organizado em sprints (Scrum).

## Equipe

| Integrante | Papel |
|---|---|
| Daniel Cruz Santana | Product Owner e banco de dados |
| Guilherme Zanelli de Novaes | Scrum Master e backend |
| Lindsay Luna Sanchez Jaldin | Desenvolvedora frontend |
| Lucas Quadros das Dores | Desenvolvedor de integração |

**Parceiro:** Secretaria de Mobilidade Urbana de São Caetano do Sul (SEMOB-SCS)
**Instituição:** Instituto Mauá de Tecnologia

## Licença

Distribuído sob a licença [MIT](LICENSE).
