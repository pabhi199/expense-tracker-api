# Expense Tracker — Full Project Summary

## Live Links

| What | URL |
|------|-----|
| **Frontend (React App)** | https://expense-tracker-api-beige-three.vercel.app |
| **Backend API** | https://expense-tracker-api-xyq3.onrender.com |
| **API Docs (Swagger)** | https://expense-tracker-api-xyq3.onrender.com/docs |
| **Source Code (GitHub)** | https://github.com/pabhi199/expense-tracker-api |

---

## What This Project Is

A full-stack personal expense tracker built from scratch. You can add, edit, and delete expenses, organize them by category, and see monthly spending summaries. It runs live on the internet for free, forever.

---

## Technology Stack

| Layer | Technology | Purpose |
|-------|-----------|---------|
| Frontend | React + Vite | The UI you see in the browser |
| Styling | Tailwind CSS | Makes the UI look good |
| Backend | FastAPI (Python) | Handles all API requests |
| Database ORM | SQLAlchemy 2.0 | Talks to the database from Python |
| Data Validation | Pydantic v2 | Validates all incoming/outgoing data |
| Database | PostgreSQL (Neon) | Stores all your expense data |
| Testing | Pytest + HTTPX | Automated tests for the backend |
| Frontend Host | Vercel | Serves the React app (free, always on) |
| Backend Host | Render | Runs the FastAPI server (free, sleeps when idle) |
| DB Host | Neon | Hosts PostgreSQL (free, always on) |

---

## Project Structure

```
expense-tracker-api/
│
├── app/                        ← Python backend (FastAPI)
│   ├── main.py                 ← App entry point, CORS, router wiring
│   ├── database.py             ← DB connection, session factory
│   ├── models.py               ← Database table definitions (Category, Expense)
│   ├── schemas.py              ← Request/response data shapes (Pydantic)
│   ├── crud.py                 ← All database operations (create, read, update, delete)
│   └── routers/
│       ├── categories.py       ← HTTP endpoints for /categories
│       └── expenses.py         ← HTTP endpoints for /expenses
│
├── frontend/                   ← React frontend (Vite)
│   └── src/
│       ├── App.jsx             ← Main app, state management, month navigation
│       ├── api.js              ← All fetch calls to the backend
│       └── components/
│           ├── Dashboard.jsx   ← Total spent card, category bar chart
│           ├── ExpenseList.jsx ← Expenses grouped by category with edit/delete
│           ├── ExpenseModal.jsx← Add/edit expense form (modal)
│           └── CategoryModal.jsx← Add new category form (modal)
│
├── tests/                      ← Automated backend tests
│   ├── conftest.py             ← Test database setup (in-memory SQLite)
│   ├── test_categories.py      ← Tests for category endpoints
│   └── test_expenses.py        ← Tests for expense endpoints + report
│
├── requirements.txt            ← Python dependencies
├── Dockerfile                  ← Container definition
├── docker-compose.yml          ← Run locally with Docker
└── .github/workflows/ci.yml    ← Runs tests automatically on every push
```

---

## How It Works (Full Flow)

### 1. Database Layer — `database.py`
The foundation. Sets up a connection to PostgreSQL (in production) or SQLite (locally). Every API request gets a fresh database session via the `get_db()` dependency, which is automatically closed after the request completes.

```
DATABASE_URL env variable → SQLAlchemy engine → SessionLocal → get_db()
```

### 2. Models — `models.py`
Defines the two database tables as Python classes:

```
Category                    Expense
─────────────               ──────────────────────────────
id (primary key)            id (primary key)
name (unique)               title
                            amount
                            spent_on (date)
                            notes (optional)
                            created_at (timestamp)
                            category_id (foreign key → Category)
```

Deleting a category automatically deletes all its expenses (cascade delete).

### 3. Schemas — `schemas.py`
Pydantic models that define exactly what data the API accepts and returns. If you send invalid data (negative amount, empty title), Pydantic rejects it automatically before it even touches the database.

```
CategoryCreate  → what you send to create a category
CategoryOut     → what you get back (includes id)
ExpenseCreate   → what you send to create an expense
ExpenseUpdate   → what you send to edit (all fields optional)
ExpenseOut      → what you get back (includes full category object)
MonthlySummary  → monthly report response (total, count, by category)
```

### 4. CRUD Layer — `crud.py`
Pure database functions — no HTTP, no web framework. Just Python functions that talk to the database. Kept separate from routers so the logic is reusable and testable.

```
Categories: get, get_by_name, list, create, delete
Expenses:   get, list (with filters), create, update, delete
Reports:    monthly_summary (SUM + GROUP BY query)
```

### 5. Routers — `routers/`
HTTP endpoints. They receive the request, call a crud function, and return the response. Kept thin on purpose — no business logic here.

```
GET    /categories              → list all categories
POST   /categories              → create a category
DELETE /categories/{id}         → delete a category

GET    /expenses                → list expenses (filter by category, date range)
POST   /expenses                → create an expense
GET    /expenses/{id}           → get one expense
PATCH  /expenses/{id}           → partial update
DELETE /expenses/{id}           → delete
GET    /expenses/report/{y}/{m} → monthly spending summary
```

### 6. Frontend — `frontend/`
React app that calls the backend API. In local development, Vite proxies `/api/*` to `localhost:8000`. In production on Vercel, it calls the Render backend URL directly via the `VITE_API_URL` environment variable.

```
User clicks button
  → React component calls api.js function
  → api.js does fetch() to backend URL
  → FastAPI validates, queries DB, returns JSON
  → React re-renders with new data
```

---

## API Endpoints (Quick Reference)

| Method | Path | What it does |
|--------|------|-------------|
| GET | `/health` | Check if server is up |
| GET | `/categories` | List all categories |
| POST | `/categories` | Create a category |
| DELETE | `/categories/{id}` | Delete category + its expenses |
| GET | `/expenses` | List expenses (supports filters) |
| POST | `/expenses` | Add a new expense |
| GET | `/expenses/{id}` | Get a single expense |
| PATCH | `/expenses/{id}` | Edit an expense |
| DELETE | `/expenses/{id}` | Delete an expense |
| GET | `/expenses/report/{year}/{month}` | Monthly spending report |

---

## Infrastructure (Free Forever)

```
[You open the app]
       ↓
  Vercel (React UI)          — always on, free
       ↓
  Render (FastAPI backend)   — free, sleeps after 15 min idle
       ↓
  Neon (PostgreSQL DB)       — always on, free, 500MB storage
```

**Note:** The backend on Render sleeps when not used for 15 minutes. The first request after sleeping takes ~30 seconds. Your data is always safe in Neon — sleeping only affects the server, not the database.

---

## Running Locally

```bash
# Clone the repo
git clone https://github.com/pabhi199/expense-tracker-api.git
cd expense-tracker-api

# Backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload
# API running at http://localhost:8000
# Swagger docs at http://localhost:8000/docs

# Frontend (new terminal)
cd frontend
npm install
npm run dev
# App running at http://localhost:5173
```

---

## Running Tests

```bash
source venv/bin/activate
pytest tests/ -v
# 13 tests, all passing
```

---

## What You Can Add Next

- **Search** — filter expenses by keyword
- **Budget limits** — set monthly limit per category, warn when exceeded
- **Yearly chart** — see all 12 months in one view
- **PWA** — install on phone home screen like a native app
- **CSV export** — download expenses as spreadsheet
- **Login/auth** — protect with a password so only you can access
