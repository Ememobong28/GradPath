from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile
from sqlalchemy.orm import Session

# 20 MB hard cap on every upload
_MAX_UPLOAD_BYTES = 20 * 1024 * 1024
_VALID_DOC_KINDS = {"transcript", "degree_audit", "course_catalog", "prereq_list"}

from app.schemas.plan import PlanGenerateRequest, PlanGenerateResponse
from app.schemas.plan_detail import PlanDetailResponse
from app.schemas.plan_compare import PlanCompareResponse
from app.schemas.risk import RiskResponse
from app.schemas.simulate import SimulateRequest, SimulateResponse
from app.schemas.course import CourseCreate, CourseCreateRequest, CourseResponse
from app.schemas.auth import LoginRequest, RegisterRequest, TokenResponse, UserOut
from app.schemas.transcript import (
    TranscriptUploadResponse,
    TranscriptConfirmRequest,
    TranscriptConfirmResponse,
    TranscriptStatusResponse,
)
from app.schemas.document import DocumentUploadResponse
from app.schemas.parse_preview import ParsePreviewResponse, DocumentParsePreview
from app.schemas.student import StudentCreateRequest, StudentResponse, StudentResumeResponse, StudentUpdateRequest
from app.schemas.program import ProgramCreateRequest, ProgramResponse
from app.schemas.requirement import RequirementCreateRequest, RequirementResponse
from app.schemas.prerequisite import PrerequisiteCreateRequest, PrerequisiteResponse
from app.services.planner import generate_plan
from app.services.students import create_student, calculate_gpa, get_student, update_student
from app.services.courses import bulk_create_courses
from app.services.transcripts import (
    create_transcript_stub,
    create_transcript_with_csv,
    create_transcript_with_pdf,
    confirm_transcript,
    get_parse_preview_for_document,
    get_transcript_status,
)
from app.services.documents import create_document, create_document_from_pdf
from app.services.pdf_parser import extract_text_from_pdf
from app.services.programs import create_program, add_requirements
from app.services.prerequisites import bulk_create_prereqs
from app.services.plans import get_plan, get_plan_risks, compare_plans
from app.services.transcript_parser import parse_catalog_csv
from app.services.simulate import simulate_plan
from app.services.auth import get_current_user, login_user, register_user
from app.core.database import get_db
from app.models.user import User
from app.models.transcript import Transcript
from app.models.plan import Plan
from app.models.student import Student

router = APIRouter(prefix="/api")


@router.post("/students", response_model=StudentResponse)
def create_student_endpoint(
    payload: StudentCreateRequest,
    db: Session = Depends(get_db),
):
    return create_student(db, payload)


@router.get("/students/{student_id}/gpa")
def get_student_gpa(student_id: int, db: Session = Depends(get_db)):
    gpa, credits = calculate_gpa(db, student_id)
    return {"student_id": student_id, "gpa": gpa, "credits": credits}


@router.post("/plans/generate", response_model=PlanGenerateResponse)
def generate_plan_endpoint(
    payload: PlanGenerateRequest,
    db: Session = Depends(get_db),
):
    return generate_plan(db, payload)


@router.post("/courses", response_model=list[CourseResponse])
def bulk_create_courses_endpoint(
    payload: CourseCreateRequest,
    db: Session = Depends(get_db),
):
    return bulk_create_courses(db, payload.courses)


@router.post("/courses/upload", response_model=list[CourseResponse])
def upload_courses_endpoint(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
):
    raw = file.file.read().decode("utf-8", errors="ignore")
    rows = parse_catalog_csv(raw)
    return bulk_create_courses(db, [CourseCreate(**row) for row in rows])


@router.post("/transcripts/upload", response_model=TranscriptUploadResponse)
def upload_transcript_endpoint(
    student_id: int,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
):
    data = file.file.read(_MAX_UPLOAD_BYTES + 1)
    if len(data) > _MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail="File exceeds 20 MB limit.")
    filename = file.filename or ""
    if filename.lower().endswith(".csv"):
        return create_transcript_with_csv(db, student_id, filename, data.decode("utf-8", errors="ignore"))
    if filename.lower().endswith(".pdf"):
        return create_transcript_with_pdf(db, student_id, filename, data)
    return create_transcript_stub(db, student_id, filename)


@router.post("/documents/upload", response_model=DocumentUploadResponse)
def upload_document_endpoint(
    student_id: int,
    kind: str = Query(..., description="transcript | degree_audit | course_catalog | prereq_list"),
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
):
    if kind not in _VALID_DOC_KINDS:
        raise HTTPException(
            status_code=422,
            detail=f"Invalid kind '{kind}'. Must be one of: {sorted(_VALID_DOC_KINDS)}",
        )
    data = file.file.read(_MAX_UPLOAD_BYTES + 1)
    if len(data) > _MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail="File exceeds 20 MB limit.")
    filename = file.filename or ""
    if filename.lower().endswith(".pdf"):
        return create_document_from_pdf(db, student_id, kind, filename, data)
    return create_document(db, student_id, kind, filename)


@router.post("/documents/preview", response_model=ParsePreviewResponse)
def preview_document_endpoint(file: UploadFile = File(...)):
    data = file.file.read(_MAX_UPLOAD_BYTES + 1)
    if len(data) > _MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail="File exceeds 20 MB limit.")
    text = extract_text_from_pdf(data)
    excerpt = text[:2000] if text else ""
    return ParsePreviewResponse(text_excerpt=excerpt, length=len(text))


@router.post("/programs", response_model=ProgramResponse)
def create_program_endpoint(
    payload: ProgramCreateRequest,
    db: Session = Depends(get_db),
):
    return create_program(db, payload)


@router.post(
    "/programs/{program_id}/requirements",
    response_model=list[RequirementResponse],
)
def add_requirements_endpoint(
    program_id: int,
    payload: RequirementCreateRequest,
    db: Session = Depends(get_db),
):
    return add_requirements(db, program_id, payload.requirements)


@router.post("/prerequisites", response_model=list[PrerequisiteResponse])
def bulk_create_prereqs_endpoint(
    payload: PrerequisiteCreateRequest,
    db: Session = Depends(get_db),
):
    return bulk_create_prereqs(db, payload.prerequisites)


# NOTE: literal path segments (/plans/simulate, /plans/compare) MUST be registered
# BEFORE the parametric route /plans/{plan_id} or FastAPI will swallow them.

@router.post("/plans/simulate", response_model=SimulateResponse)
def simulate_plan_endpoint(
    payload: SimulateRequest,
    db: Session = Depends(get_db),
):
    return simulate_plan(db, payload)


@router.get("/plans/compare", response_model=PlanCompareResponse)
def compare_plans_endpoint(
    baseline_plan_id: int,
    simulated_plan_id: int,
    db: Session = Depends(get_db),
):
    result = compare_plans(db, baseline_plan_id, simulated_plan_id)
    if result is None:
        return PlanCompareResponse(
            baseline_plan_id=baseline_plan_id,
            simulated_plan_id=simulated_plan_id,
            term_count_diff=0,
            added_courses=[],
            removed_courses=[],
        )
    return PlanCompareResponse(**result)


@router.get("/plans/{plan_id}", response_model=PlanDetailResponse)
def get_plan_endpoint(plan_id: int, db: Session = Depends(get_db)):
    plan = get_plan(db, plan_id)
    if plan is None:
        raise HTTPException(status_code=404, detail="Plan not found.")
    return plan


@router.get("/plans/{plan_id}/risks", response_model=list[RiskResponse])
def get_plan_risks_endpoint(plan_id: int, db: Session = Depends(get_db)):
    return get_plan_risks(db, plan_id)


# ── Auth ──────────────────────────────────────────────────────────────────────

@router.post("/auth/register", response_model=TokenResponse, status_code=201)
def register_endpoint(payload: RegisterRequest, db: Session = Depends(get_db)):
    return register_user(db, payload)


@router.post("/auth/login", response_model=TokenResponse)
def login_endpoint(payload: LoginRequest, db: Session = Depends(get_db)):
    return login_user(db, payload)


@router.get("/me", response_model=UserOut)
def me_endpoint(current_user: User = Depends(get_current_user)):
    return current_user


# ── Students ──────────────────────────────────────────────────────────────────
@router.get("/students/lookup")
def lookup_student_endpoint(
    school_student_id: str = Query(..., description="School-issued student ID"),
    db: Session = Depends(get_db),
):
    """
    Look up a returning student by their school-issued student ID.
    Returns the DB record id, display name, major, and the id of their
    most recently generated plan (if any).
    """
    students = (
        db.query(Student)
        .filter(Student.student_id == school_student_id)
        .order_by(Student.id)
        .all()
    )
    if not students:
        raise HTTPException(status_code=404, detail="No student found with that student ID.")

    # Pick the record with the most transcript data
    from app.models.transcript import TranscriptCourse as TC
    best = students[0]
    best_count = (
        db.query(TC)
        .join(Transcript, TC.transcript_id == Transcript.id)
        .filter(Transcript.student_id == best.id)
        .count()
    )
    for candidate in students[1:]:
        count = (
            db.query(TC)
            .join(Transcript, TC.transcript_id == Transcript.id)
            .filter(Transcript.student_id == candidate.id)
            .count()
        )
        if count > best_count:
            best = candidate
            best_count = count

    latest_plan = (
        db.query(Plan)
        .filter(Plan.student_id == best.id)
        .order_by(Plan.id.desc())
        .first()
    )

    return {
        "db_id": best.id,
        "first_name": best.first_name,
        "last_name": best.last_name,
        "major": best.major,
        "school": best.school,
        "plan_id": latest_plan.id if latest_plan else None,
    }

@router.get("/students/{student_id}", response_model=StudentResumeResponse)
def get_student_endpoint(student_id: int, db: Session = Depends(get_db)):
    student = get_student(db, student_id)
    # Attach latest transcript info for the resume-where-you-left-off flow
    latest = (
        db.query(Transcript)
        .filter(Transcript.student_id == student_id)
        .order_by(Transcript.uploaded_at.desc())
        .first()
    )
    latest_plan = (
        db.query(Plan)
        .filter(Plan.student_id == student_id)
        .order_by(Plan.id.desc())
        .first()
    )
    result = StudentResumeResponse.model_validate(student)
    if latest:
        result.transcript_id = latest.id
        result.transcript_status = latest.status
    if latest_plan:
        result.plan_id = latest_plan.id
    return result


@router.put("/students/{student_id}", response_model=StudentResumeResponse)
def update_student_endpoint(
    student_id: int,
    payload: StudentUpdateRequest,
    db: Session = Depends(get_db),
):
    student = update_student(db, student_id, payload)
    latest = (
        db.query(Transcript)
        .filter(Transcript.student_id == student_id)
        .order_by(Transcript.uploaded_at.desc())
        .first()
    )
    latest_plan = (
        db.query(Plan)
        .filter(Plan.student_id == student_id)
        .order_by(Plan.id.desc())
        .first()
    )
    result = StudentResumeResponse.model_validate(student)
    if latest:
        result.transcript_id = latest.id
        result.transcript_status = latest.status
    if latest_plan:
        result.plan_id = latest_plan.id
    return result


# ── Documents ─────────────────────────────────────────────────────────────────

@router.get("/documents/{document_id}/parse", response_model=DocumentParsePreview)
def parse_document_endpoint(document_id: int, db: Session = Depends(get_db)):
    return get_parse_preview_for_document(db, document_id)


# ── Transcripts ───────────────────────────────────────────────────────────────

@router.get("/transcripts/{student_id}", response_model=TranscriptStatusResponse)
def get_transcript_status_endpoint(student_id: int, db: Session = Depends(get_db)):
    return get_transcript_status(db, student_id)


@router.post("/transcripts/confirm", response_model=TranscriptConfirmResponse)
def confirm_transcript_endpoint(
    payload: TranscriptConfirmRequest,
    db: Session = Depends(get_db),
):
    return confirm_transcript(db, payload)


# ── Simulations ───────────────────────────────────────────────────────────────

@router.post("/simulations/run", response_model=SimulateResponse)
def run_simulation_endpoint(
    payload: SimulateRequest,
    db: Session = Depends(get_db),
):
    return simulate_plan(db, payload)
