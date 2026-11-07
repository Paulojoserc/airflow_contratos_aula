# Airflow - ETL de Contratos do Ceará Transparente

Pipeline de dados que coleta os contratos públicos da API do Ceará Transparente, prepara os dados com pandas e grava no PostgreSQL. A orquestração é feita pelo Apache Airflow 3.0.2, tudo em Docker Compose.

## Objetivo

Carregar os contratos de 2025 e 2026 na tabela `contratos` e executar a carga diariamente às 19:00 (horário de Fortaleza).

## Arquitetura

```
API Ceará Transparente
        │
        ▼
  Airflow (DAG api_contratos_ceara_postgresql)
  coletar → preparar → salvar
        │
        ▼
  PostgreSQL 16 (banco convenios, tabela contratos)
```

Serviços do `docker-compose.yaml`:

| Serviço | Função |
|---|---|
| `postgres` | Banco de dados (metadados do Airflow e tabelas de dados) |
| `airflow-init` | Executa a migração do banco e termina |
| `airflow-apiserver` | Interface web em `http://localhost:8080` |
| `airflow-scheduler` | Agenda e dispara as execuções |
| `airflow-dag-processor` | Lê os arquivos da pasta `dags/` |

## Estrutura

```
.
├── dags/
│   ├── dag_contratos.py      # ETL de contratos (tarefa principal)
│   └── dag_convenios.py      # ETL de convênios
├── initdb/
│   ├── 01-databases.sql      # usuário e bancos
│   ├── 02-convenios.sql      # tabela convenios
│   └── 03-contratos.sql      # tabela contratos
├── logs/                     # logs do Airflow (ignorados pelo Git)
├── plugins/
├── Dockerfile                # imagem do Airflow com pandas
├── docker-compose.yaml
├── .env.example              # modelo das variáveis de ambiente
└── .gitignore
```

## Pré-requisitos

- Docker Desktop (Windows) ou Docker Engine (Linux)
- Git

Não é necessário instalar Python, Airflow ou PostgreSQL na máquina.

## Configuração

Copie o modelo de variáveis e preencha:

```bash
cp .env.example .env
```

Gere as chaves:

```bash
docker run --rm apache/airflow:3.0.2-python3.12 python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
docker run --rm python:3.12-slim python -c "import secrets; print(secrets.token_hex(32))"
```

O arquivo `.env` não vai para o repositório (está no `.gitignore`).

## Como executar

```bash
docker compose up -d --build
```

Acesse `http://localhost:8080` e entre com o usuário `admin`. A senha fica em:

```bash
docker compose exec airflow-apiserver cat /opt/airflow/simple_auth_manager_passwords.json.generated
```

Na interface:

1. Abra a DAG `api_contratos_ceara_postgresql`.
2. Ative a DAG e clique em **Trigger**.
3. Acompanhe as tasks `coletar`, `preparar` e `salvar`.

## Verificando os dados

```bash
docker compose exec postgres psql -U airflow -d convenios -c "SELECT count(*) FROM contratos;"
```

## Agendamento

A DAG roda todos os dias às 19:00 (`America/Fortaleza`). Cada execução baixa os contratos desde 01/01/2025 até o fim do mês da execução. Registros já existentes são ignorados pela cláusula `ON CONFLICT (id) DO NOTHING`.

## Solução de problemas

- **Tabela vazia após a execução:** veja os logs da task `coletar` (quantos registros foram coletados) e da task `salvar`.
- **Erro de permissão em `logs` ou `plugins` (Linux):** `sudo chown -R 50000:0 logs plugins dags`.
- **Alterou um arquivo de `initdb/`:** os scripts só rodam com um volume novo. Use `docker compose down -v` para recriar o banco. Isso apaga os dados.
- **Porta em uso:** altere o lado esquerdo do mapeamento em `ports` no `docker-compose.yaml`.

## Deploy

O deploy é feito no Coolify a partir deste repositório, usando o `docker-compose.yaml`. As variáveis de ambiente são cadastradas no Coolify, não no repositório.
