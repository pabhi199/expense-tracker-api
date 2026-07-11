# Expense Tracker API

A small but complete end-to-end Python project: REST API → database → tests → Docker → CI. Built with FastAPI, SQLAlchemy 2.0, and Pytest.

## Features

- CRUD for expenses and categories
- Filtering by category and date range, with pagination
- Monthly spending report grouped by category
- Full test suite with isolated in-memory databases
- Dockerized, with GitHub Actions CI (tests + container smoke test)

## Run locally

```bash
python -m venv .venv && source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```

Open http://localhost:8000/docs for interactive Swagger UI.

## Run tests

```bash
pytest -v
```

## Run with Docker

```bash
docker compose up --build
```

## Quick API tour

```bash
# create a category
curl -X POST localhost:8000/categories -H "Content-Type: application/json" -d '{"name": "Food"}'

# add an expense
curl -X POST localhost:8000/expenses -H "Content-Type: application/json" \
  -d '{"title": "Lunch", "amount": 250, "spent_on": "2026-07-11", "category_id": 1}'

# monthly report
curl localhost:8000/expenses/report/2026/7
```

## Architecture

```
app/
├── main.py        # FastAPI app, startup, router wiring
├── database.py    # engine, session factory, get_db dependency
├── models.py      # SQLAlchemy ORM models
├── schemas.py     # Pydantic request/response schemas
├── crud.py        # all DB operations (routers stay thin)
└── routers/       # HTTP endpoints only
```

## Enhancement roadmap (great tasks to try with Claude)

Each of these is a realistic, self-contained enhancement — ideal for testing AI-assisted development:

1. **Auth** — add JWT authentication so each user has their own expenses
2. **Migrations** — replace `create_all` with Alembic
3. **Postgres** — swap SQLite for Postgres in docker-compose
4. **Budgets** — add monthly budget limits per category with alerts
5. **CSV export** — endpoint to export expenses as a CSV file
6. **Caching** — cache the monthly report with invalidation on writes
7. **Rate limiting** — protect the API with slowapi
8. **Observability** — structured logging + a `/metrics` Prometheus endpoint
9. **CD** — extend CI to push the image to a registry and deploy (Railway/Render/Fly.io)
