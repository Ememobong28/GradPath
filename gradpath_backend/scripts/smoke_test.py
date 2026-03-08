"""
GradPath smoke test — runs the full happy-path flow against localhost:8000.
Usage:  python scripts/smoke_test.py [path/to/transcript.pdf]
"""
import sys
import json
import requests

BASE = "http://localhost:8000/api"
PDF  = sys.argv[1] if len(sys.argv) > 1 else None

GREEN  = "\033[92m"
RED    = "\033[91m"
YELLOW = "\033[93m"
RESET  = "\033[0m"
BOLD   = "\033[1m"

def ok(label, data=None):
    print(f"{GREEN}✓{RESET} {BOLD}{label}{RESET}")
    if data:
        print(f"  {json.dumps(data, indent=2)[:300]}")

def fail(label, r):
    print(f"{RED}✗{RESET} {BOLD}{label}{RESET}  [{r.status_code}]")
    try:
        print(f"  {json.dumps(r.json(), indent=2)[:400]}")
    except Exception:
        print(f"  {r.text[:400]}")
    sys.exit(1)

def step(n, label):
    print(f"\n{YELLOW}{'─'*50}{RESET}")
    print(f"{YELLOW}Step {n}: {label}{RESET}")
    print(f"{YELLOW}{'─'*50}{RESET}")

# ── 1. Register ───────────────────────────────────────────────
step(1, "Register")
r = requests.post(f"{BASE}/auth/register",
    json={"email": "smoke@gradpath.dev", "password": "Smoke2026!"})
if r.status_code == 201:
    token = r.json()["access_token"]
    ok("Registered", {"user_id": r.json()["user_id"], "token": token[:30] + "..."})
elif r.status_code == 400 and "already" in r.text.lower():
    # Reuse — login instead
    print("  (user exists — logging in)")
    r = requests.post(f"{BASE}/auth/login",
        json={"email": "smoke@gradpath.dev", "password": "Smoke2026!"})
    if r.status_code != 200: fail("Login fallback", r)
    token = r.json()["access_token"]
    ok("Logged in", {"user_id": r.json()["user_id"]})
else:
    fail("Register", r)

HEADERS = {"Authorization": f"Bearer {token}"}

# ── 2. /me ────────────────────────────────────────────────────
step(2, "GET /me")
r = requests.get(f"{BASE}/me", headers=HEADERS)
if r.status_code == 200:
    ok("/me", r.json())
else:
    fail("/me", r)

# ── 3. Create student ─────────────────────────────────────────
step(3, "POST /students")
r = requests.post(f"{BASE}/students", json={
    "first_name": "Immanuella",
    "last_name": "Umoren",
    "max_credits": 18,
    "summer_ok": False,
    "target_grad_term": "Spring 2027",
})
if r.status_code not in (200, 201): fail("Create student", r)
student = r.json()
SID = student["id"]
ok(f"Student created  id={SID}", student)

# ── 4. GET student (resume) ───────────────────────────────────
step(4, "GET /students/{id}")
r = requests.get(f"{BASE}/students/{SID}")
if r.status_code == 200:
    ok("GET student", r.json())
else:
    fail("GET student", r)

# ── 5. Upload transcript PDF ──────────────────────────────────
step(5, "POST /documents/upload  (transcript PDF)")
if not PDF:
    print(f"  {YELLOW}SKIP — no PDF path provided{RESET}")
    DID = None
else:
    with open(PDF, "rb") as f:
        r = requests.post(
            f"{BASE}/documents/upload",
            params={"student_id": SID, "kind": "transcript"},
            files={"file": (PDF.split("/")[-1], f, "application/pdf")},
        )
    if r.status_code not in (200, 201): fail("Upload PDF", r)
    doc = r.json()
    DID = doc["id"]
    ok(f"Document uploaded  id={DID}", doc)

# ── 6. Parse document ─────────────────────────────────────────
step(6, "GET /documents/{id}/parse")
if DID is None:
    print(f"  {YELLOW}SKIP — no document uploaded{RESET}")
else:
    r = requests.get(f"{BASE}/documents/{DID}/parse")
    if r.status_code == 200:
        parsed = r.json()
        ok(f"Parsed  {len(parsed.get('detected_courses', []))} courses detected", parsed)
    else:
        fail("Parse document", r)

# ── 7. Transcript status ──────────────────────────────────────
step(7, "GET /transcripts/{student_id}")
r = requests.get(f"{BASE}/transcripts/{SID}")
if r.status_code == 200:
    ok("Transcript status", r.json())
else:
    fail("Transcript status", r)

# ── 8. Confirm transcript ─────────────────────────────────────
step(8, "POST /transcripts/confirm")
courses = (
    parsed.get("detected_courses", [])
    if DID
    else [{"code": "CS101", "title": "Intro CS", "credits": 3, "grade": "A", "term": "Fall 2023"}]
)
if not courses:
    courses = [{"code": "CS101", "title": "Intro CS", "credits": 3, "grade": "A", "term": "Fall 2023"}]

r = requests.post(f"{BASE}/transcripts/confirm",
    json={"student_id": SID, "courses": courses[:5]})  # cap to 5 for display
if r.status_code in (200, 201):
    ok("Transcript confirmed", r.json())
else:
    fail("Confirm transcript", r)

# ── 9. Generate plan ──────────────────────────────────────────
step(9, "POST /plans/generate")
r = requests.post(f"{BASE}/plans/generate", json={
    "student_id": SID,
    "max_credits": 15,
    "summer_ok": False,
    "target_grad_term": "Spring 2027",
})
if r.status_code in (200, 201):
    plan = r.json()
    PID = plan.get("plan_id")
    sems = plan.get("semesters", [])
    risks = plan.get("risk_summary", [])
    ok(f"Plan generated  id={PID}  {len(sems)} semesters  {len(risks)} risks")
    for s in sems[:4]:
        print(f"    {s.get('term','?'):20s}  {s.get('credits','?')} cr  {s.get('courses',[])} ")
    if risks:
        print(f"  risks: {risks[:3]}")
else:
    fail("Generate plan", r)

# ── 10. Simulate plan ─────────────────────────────────────────
step(10, "POST /plans/simulate")
if PID:
    r = requests.post(f"{BASE}/plans/simulate",
        json={"plan_id": PID, "max_credits": 12})
    if r.status_code in (200, 201):
        ok("Simulation run", r.json())
    else:
        fail("Simulate plan", r)
else:
    print(f"  {YELLOW}SKIP — no plan_id{RESET}")

print(f"\n{GREEN}{'═'*50}{RESET}")
print(f"{GREEN}{BOLD}  All smoke tests passed ✓{RESET}")
print(f"{GREEN}{'═'*50}{RESET}\n")
