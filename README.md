# GradPath

**GradPath** is a graduation planning and risk optimization platform that transforms a student's degree audit and program requirements into a personalized, term-by-term graduation plan.

> Combines prerequisite graph algorithms, constraint-based scheduling, and machine learning to help students graduate on time.

---

## Demo

[▶ Watch Demo](https://drive.google.com/file/d/1cHZ3BcIEC6xwpzkJvryU9W0fxVtJ4G_c/view?usp=sharing)

---

## Screenshots

### Landing Page

<img src="docs/screenshots/landing%20page%201.png" width="100%"/>
<img src="docs/screenshots/landing%20page%202.png" width="100%"/>
<img src="docs/screenshots/landing%20page%203.png" width="100%"/>
<img src="docs/screenshots/landing%20page%204.png" width="100%"/>
<img src="docs/screenshots/landing%20page%205.png" width="100%"/>

### Sign In

<img src="docs/screenshots/Sign-in%20screen.png" width="100%"/>

### Onboarding

<img src="docs/screenshots/onboarding.png" width="100%"/>

### Dashboard

<img src="docs/screenshots/Dashboard.png" width="100%"/>

### My Plan

<img src="docs/screenshots/Plan.png" width="100%"/>

### What-If Simulator

<img src="docs/screenshots/What-if%20simulator.png" width="100%"/>

### Risk Analysis

<img src="docs/screenshots/Risk%20Page.png" width="100%"/>

### Export

<img src="docs/screenshots/Export%20Page%20.png" width="100%"/>

---

## Deployment

### Frontend — GitHub Pages

The frontend is automatically deployed to **GitHub Pages** on every push to `main`.

**Live site:** `https://ememobong28.github.io/GradPath/`

**How it works** (via [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml)):
1. Push to `main` triggers the workflow
2. GitHub Actions checks out the repo and installs Flutter 3.27.1
3. Runs `flutter build web --release` with the Render backend URL injected at build time
4. Deploys the build output from `gradpath_frontend/build/web` to GitHub Pages

### Backend — Render

The FastAPI backend is deployed on **Render** with a managed PostgreSQL database.

**API base URL:** `https://gradpath-backend.onrender.com`

**Services:**
- `gradpath-backend` — FastAPI web service (Docker, auto-deployed from `main`)
- `gradpath-db` — PostgreSQL 16 managed database

**How it works** (via [`render.yaml`](render.yaml)):
1. Push to `main` triggers a Render deploy
2. Docker builds the image from `gradpath_backend/Dockerfile`
3. `DATABASE_URL` is automatically injected from the managed Postgres instance
4. On startup, SQLAlchemy creates all tables automatically

> **Note:** The free Render tier spins down after 15 minutes of inactivity. The first request after idle may take ~30 seconds to wake up.

---

## Features

- **Transcript Ingestion** — Upload a PDF or CSV transcript; courses are auto-extracted and confidence-scored for user review
- **Prerequisite Graph Engine** — Models all course dependencies as a directed acyclic graph using Kahn's topological sort
- **Constraint-Based Scheduler** — Greedy term-by-term packing that enforces prerequisites, co-requisites, credit caps, semester availability, and honors restrictions
- **Graduation Forecast** — Estimates earliest possible graduation term and assigns a delay risk score with plain-language explanations
- **What-If Simulator** — Instantly see the impact of reducing course load, adding summer terms, or simulating a failed class
- **Honors Support** — Tracks honors-only courses, thesis sequencing, and honors-specific requirements
- **Advisor-Ready Export** — Generates a downloadable PDF summary of the graduation plan and identified risks
- **GPA Tracking** — Calculates weighted GPA from confirmed transcript courses

---

## Tech Stack

| Layer | Technology |
|---|---|
| Frontend | Flutter 3.5 (Dart) — web, iOS, Android, desktop |
| Backend | FastAPI (Python 3.10+) |
| Database | PostgreSQL 16 |
| ORM | SQLAlchemy 2.0 |
| Auth | JWT + bcrypt (passlib) |
| PDF Parsing | pypdf |
| ML / Scheduling | Scikit-learn + custom Python engine |
| Infrastructure | Docker Compose |

---

## Project Structure

```
GradPath/
├── gradpath_frontend/       # Flutter application
│   └── lib/
│       ├── main.dart                    # Landing page
│       ├── onboarding_screen.dart       # 5-step onboarding wizard
│       ├── returning_student_screen.dart
│       ├── gradpath_sidebar.dart        # Main dashboard shell
│       ├── dashboard_screen.dart        # GPA, credits, forecast
│       ├── schedule_screen.dart         # Semester-by-semester plan
│       ├── whatif_screen.dart           # Simulation controls
│       ├── risk_screen.dart             # Bottleneck warnings
│       ├── export_screen.dart           # PDF export
│       └── gradpath_theme.dart          # Color system + typography
│
└── gradpath_backend/        # FastAPI application
    └── app/
        ├── api/routes.py                # 20+ REST endpoints
        ├── models/                      # SQLAlchemy ORM models (15 tables)
        ├── schemas/                     # Pydantic request/response schemas
        ├── services/
        │   ├── graph.py                 # Prerequisite DAG (Kahn's algorithm)
        │   ├── scheduler.py             # Constraint-based term scheduler
        │   ├── planner.py               # Plan generation orchestrator
        │   ├── simulate.py              # What-if engine
        │   ├── transcript_parser.py     # PDF + CSV transcript parsing
        │   ├── pdf_parser.py            # Raw PDF text extraction
        │   └── students.py             # GPA calculation
        └── main.py                      # App entry point + CORS
```

---

## How It Works

### Plan Generation

```
Upload Transcript (PDF/CSV)
        ↓
Auto-extract courses → User confirms
        ↓
POST /api/plans/generate
        ↓
Build prerequisite DAG → Topological sort
        ↓
Infer start term from transcript
        ↓
Greedy constraint-based schedule
        ↓
Detect bottlenecks → Persist risks
        ↓
Render term-by-term plan
```

### Core Algorithms

**Prerequisite Graph** (`services/graph.py`)
- Courses are nodes; prerequisites are directed edges
- Kahn's algorithm performs topological sort and detects cycles
- Bottlenecks (single-path dependencies) are flagged as high-risk

**Constraint-Based Scheduler** (`services/scheduler.py`)
- Fills terms greedily while enforcing:
  - All prerequisites completed in prior terms
  - Co-requisites co-enrolled in the same term
  - Credits per term ≤ student's max (configurable 6–30)
  - Course offered in the current season (Fall / Spring / Summer)
  - Honors-only courses filtered for non-honors students
  - Optional: suppress summer terms

**Simulation Engine** (`services/simulate.py`)
- Temporarily overrides student settings (max credits, summer availability)
- Regenerates a full plan and computes a risk score (0–100)
- Restores original settings after simulation

---

## API Reference

| Method | Endpoint | Description |
|---|---|---|
| `POST` | `/api/auth/register` | Register new user |
| `POST` | `/api/auth/login` | Login, returns JWT |
| `GET` | `/api/me` | Current authenticated user |
| `POST` | `/api/students` | Create student record |
| `GET` | `/api/students/{id}` | Get student + transcript/plan state |
| `PUT` | `/api/students/{id}` | Update preferences |
| `GET` | `/api/students/{id}/gpa` | Calculate GPA |
| `POST` | `/api/transcripts/upload` | Upload PDF or CSV transcript |
| `GET` | `/api/transcripts/{student_id}` | Get parsed transcript |
| `POST` | `/api/transcripts/confirm` | Save confirmed courses |
| `POST` | `/api/plans/generate` | Generate graduation plan |
| `GET` | `/api/plans/{plan_id}` | Fetch plan with terms |
| `GET` | `/api/plans/{plan_id}/risks` | Get bottleneck risks |
| `POST` | `/api/plans/simulate` | Run what-if simulation |
| `POST` | `/api/courses/upload` | Upload CSV course catalog |
| `POST` | `/api/documents/upload` | Upload catalog/prereq PDFs |
| `GET` | `/api/documents/{id}/parse` | Parse uploaded document |

---

## Getting Started

### Prerequisites

- [Flutter 3.5+](https://flutter.dev/docs/get-started/install)
- Python 3.10+
- Docker + Docker Compose
- PostgreSQL 16 (via Docker)

### 1. Start the Database

```bash
docker-compose up db
```

### 2. Start the Backend

```bash
cd gradpath_backend
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # update values
uvicorn app.main:app --reload
```

Backend runs at `http://localhost:8000`. Interactive docs at `http://localhost:8000/docs`.

### 3. Start the Frontend

```bash
cd gradpath_frontend
flutter pub get
flutter run -d chrome --dart-define=COLLEGE_SCORECARD_API_KEY=YOUR_KEY
```

Frontend runs at `http://localhost:PORT` (Flutter assigns port automatically).

> Get a free College Scorecard API key at [api.data.gov/signup](https://api.data.gov/signup/)

---

## Database Schema (Key Tables)

| Table | Purpose |
|---|---|
| `users` | Authentication credentials |
| `students` | Academic profile (major, honors, credit prefs) |
| `transcripts` | Uploaded transcript metadata |
| `transcript_courses` | Parsed courses with confidence scores |
| `courses` | Course catalog (availability, credits, honors flag) |
| `prerequisites` | Course dependency edges (required / coreq / optional) |
| `plans` | Generated graduation plans |
| `plan_terms` | Semesters within a plan |
| `plan_items` | Courses within a semester |
| `risks` | Detected bottlenecks and delay factors |
| `programs` | Degree programs |
| `requirements` | Degree requirement groups (core / elective) |

---

## Running Tests

```bash
cd gradpath_backend
python scripts/smoke_test.py
```

The smoke test runs a full happy-path: register → create student → upload transcript → confirm courses → generate plan → simulate what-if.

---

## Environment Variables

| Variable | Description | Default |
|---|---|---|
| `DATABASE_URL` | PostgreSQL connection string | `postgresql://gradpath:gradpath_pw@localhost/gradpath` |
| `SECRET_KEY` | JWT signing secret | — |
| `ALGORITHM` | JWT algorithm | `HS256` |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | Token lifetime | `60` |

---

## Roadmap

- [ ] Advisor-facing dashboard
- [ ] Support for double majors and minors
- [ ] Institution-level analytics
- [ ] CI/CD pipeline (GitHub Actions)
- [ ] Production deployment with restricted CORS
- [ ] ML model for workload intensity prediction

---

## License

All rights reserved.
