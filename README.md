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

| Serviço | Porta no host | Função |
|---|---|---|
| `postgres` | 5432 | Banco de dados (metadados do Airflow e tabelas de dados) |
| `airflow-init` | - | Executa a migração do banco e termina |
| `airflow-apiserver` | 8081 | Interface web (porta 8080 dentro do container) |
| `airflow-scheduler` | - | Agenda e dispara as execuções |
| `airflow-dag-processor` | - | Lê os arquivos da pasta `dags/` |

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
├── plugins/
├── Dockerfile                # imagem do Airflow com pandas, dags e plugins
├── Dockerfile.postgres       # imagem do Postgres com os scripts de initdb
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

Acesse `http://localhost:8081` e entre com o usuário `admin`. A senha é gerada a cada subida do container. Para consultá-la:

```bash
docker logs $(docker ps -q -f name=apiserver | head -n 1) 2>&1 | grep "Password for user"
```

Na interface:

1. Pause a DAG `api_convenios_ceara_postgresql`, se estiver ativa.
2. Abra a DAG `api_contratos_ceara_postgresql`, ative-a e clique em **Trigger**.
3. Acompanhe as tasks `coletar`, `preparar` e `salvar`.

## Verificando os dados

```bash
docker exec $(docker ps -q -f name=postgres | head -n 1) psql -U airflow -d convenios -c "SELECT count(*) FROM contratos;"
```

## Agendamento

A DAG roda todos os dias às 19:00 (`America/Fortaleza`). Cada execução baixa os contratos desde 01/01/2025 até o fim do mês da execução. Registros já existentes são ignorados pela cláusula `ON CONFLICT (id) DO NOTHING`.

## Atualizando DAGs e scripts

Os arquivos de `dags/`, `plugins/` e `initdb/` são copiados para as imagens durante o build. Por isso, cada alteração exige um novo build:

```bash
docker compose up -d --build
```

No Coolify, o mesmo efeito é obtido com commit, push e **Redeploy**.

Os scripts de `initdb/` só rodam quando o volume `pg_data` é criado. Se você alterar um desses arquivos, remova o volume para recriar o banco. Isso apaga os dados:

```bash
docker compose down -v
docker compose up -d --build
```

## Solução de problemas

- **Tabela vazia após a execução:** veja os logs da task `coletar` (quantos registros foram coletados) e da task `salvar`.
- **Interface sem DAGs:** confirme que os arquivos chegaram ao container com `docker exec <apiserver> ls /opt/airflow/dags`.
- **CPU alta no `airflow-apiserver`:** verifique se a variável `AIRFLOW__API__WORKERS` está definida como `1`.
- **Erro de permissão em `logs`:** os logs ficam em volume nomeado (`airflow_logs`), então não é preciso ajustar permissões de pastas.
- **Porta em uso:** altere o lado esquerdo do mapeamento em `ports` no `docker-compose.yaml`.

## Deploy

O deploy é feito no Coolify a partir deste repositório, usando o `docker-compose.yaml`. As variáveis de ambiente são cadastradas no Coolify, não no repositório.
