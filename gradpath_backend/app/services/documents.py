from sqlalchemy.orm import Session

from app.models.course import Course
from app.models.document import DocumentUpload
from app.models.prerequisite import Prerequisite
from app.services.pdf_parser import extract_text_from_pdf
from app.services.transcript_parser import parse_catalog_text, parse_prereq_text


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
