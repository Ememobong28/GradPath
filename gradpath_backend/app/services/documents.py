from sqlalchemy.orm import Session

from app.models.course import Course
from app.models.document import DocumentUpload
from app.models.prerequisite import Prerequisite
from app.models.program import Program
from app.models.requirement import Requirement, RequirementCourse
from app.services.pdf_parser import extract_text_from_pdf
from app.services.transcript_parser import parse_catalog_text, parse_degree_audit_text, parse_prereq_text


def create_document(db: Session, student_id: int, kind: str, filename: str | None) -> DocumentUpload:
    doc = DocumentUpload(student_id=student_id, kind=kind, filename=filename)
    db.add(doc)
    db.commit()
    db.refresh(doc)
    return doc


def create_document_from_pdf(
    db: Session,
    student_id: int,
    kind: str,
    filename: str | None,
    data: bytes,
) -> DocumentUpload:
    raw_text = extract_text_from_pdf(data)
    status = "parsed_raw" if raw_text else "received"
    doc = DocumentUpload(
        student_id=student_id,
        kind=kind,
        filename=filename,
        raw_text=raw_text,
        status=status,
    )
    db.add(doc)
    db.commit()
    db.refresh(doc)

    if raw_text:
        if kind == "course_catalog":
            _ingest_catalog(db, raw_text)
        elif kind == "prereq_list":
            _ingest_prereqs(db, raw_text)
        elif kind == "degree_audit":
            _ingest_degree_audit(db, student_id, raw_text)
    db.commit()
    return doc


def _ingest_catalog(db: Session, raw_text: str):
    for row in parse_catalog_text(raw_text):
        code = row.get("code")
        if not code:
            continue
        existing = db.query(Course).filter(Course.code == code).first()
        if existing:
            existing.title = existing.title or row.get("title")
            existing.credits = existing.credits or row.get("credits")
            existing.availability = existing.availability or row.get("availability")
            if row.get("honors_only"):
                existing.honors_only = True
            db.add(existing)
        else:
            db.add(
                Course(
                    code=code,
                    title=row.get("title"),
                    credits=row.get("credits"),
                    availability=row.get("availability"),
                    honors_only=row.get("honors_only") or False,
                )
            )


def _ingest_prereqs(db: Session, raw_text: str):
    for row in parse_prereq_text(raw_text):
        course_code = row.get("course_code")
        prereq_code = row.get("prereq_code")
        relation = row.get("relation") or "required"
        if not course_code or not prereq_code:
            continue
        existing = (
            db.query(Prerequisite)
            .filter(
                Prerequisite.course_code == course_code,
                Prerequisite.prereq_code == prereq_code,
                Prerequisite.relation == relation,
            )
            .first()
        )
        if existing:
            continue
        db.add(
            Prerequisite(
                course_code=course_code,
                prereq_code=prereq_code,
                relation=relation,
            )
        )


def _ingest_degree_audit(db: Session, student_id: int, raw_text: str):
    """Parse a degree audit PDF and store the required courses.

    Steps:
    1. Upsert every course found in the audit into the courses table so the
       scheduler has credit/availability data for them.
    2. Create (or replace) a student-scoped Program so the planner can later
       restrict scheduling to only the courses this student actually needs.
    """
    rows = parse_degree_audit_text(raw_text)
    if not rows:
        return

    # ── 1. Upsert courses ────────────────────────────────────────────────────
    for row in rows:
        code = row.get("code")
        if not code:
            continue
        existing = db.query(Course).filter(Course.code == code).first()
        if existing:
            existing.title = existing.title or row.get("title")
            existing.credits = existing.credits or row.get("credits")
            db.add(existing)
        else:
            db.add(
                Course(
                    code=code,
                    title=row.get("title"),
                    credits=row.get("credits"),
                )
            )
    db.flush()

    # ── 2. Create / replace student-scoped program ───────────────────────────
    program = (
        db.query(Program)
        .filter(Program.student_id == student_id)
        .first()
    )
    if program:
        # Drop existing requirement courses so we start fresh
        for req in db.query(Requirement).filter(Requirement.program_id == program.id).all():
            db.query(RequirementCourse).filter(
                RequirementCourse.requirement_id == req.id
            ).delete()
            db.delete(req)
        db.flush()
    else:
        program = Program(student_id=student_id, name="Degree Audit")
        db.add(program)
        db.flush()

    requirement = Requirement(
        program_id=program.id,
        name="Required Courses",
        kind="core",
    )
    db.add(requirement)
    db.flush()

    seen: set[str] = set()
    for row in rows:
        code = row.get("code")
        if not code or code in seen:
            continue
        seen.add(code)
        db.add(RequirementCourse(requirement_id=requirement.id, course_code=code))
    db.flush()
