from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.models.course import Course
from app.models.document import DocumentUpload
from app.models.transcript import Transcript, TranscriptCourse
from app.schemas.transcript import ConfirmCourse, TranscriptConfirmRequest
from app.services.transcript_parser import (
    parse_transcript_csv,
    parse_transcript_text,
)
from app.services.pdf_parser import extract_text_from_pdf


def get_transcript_status(db: Session, student_id: int) -> dict:
    """GET /api/transcripts/{student_id} — returns confirmed courses or current status."""
    transcript = (
        db.query(Transcript)
        .filter(Transcript.student_id == student_id)
        .order_by(Transcript.uploaded_at.desc())
        .first()
    )
    if transcript is None:
        return {
            "student_id": student_id,
            "transcript_id": None,
            "status": "none",
            "courses": [],
            "needs_review": False,
        }

    courses = []
    needs_review = False
    if transcript.status == "confirmed":
        courses = [
            {
                "id": c.id,
                "course_code": c.course_code,
                "course_title": c.course_title,
                "credits": c.credits,
                "term": c.term,
                "grade": c.grade,
                "confidence": c.confidence,
            }
            for c in db.query(TranscriptCourse)
            .filter(TranscriptCourse.transcript_id == transcript.id)
            .all()
        ]
    elif transcript.status == "parsed_raw":
        # Prefer already-saved DB rows (written at upload time) over re-parsing
        # raw text on every request, which causes the generic regex to produce
        # false-positive "courses" from addresses, IDs, etc. in the PDF.
        db_courses = (
            db.query(TranscriptCourse)
            .filter(TranscriptCourse.transcript_id == transcript.id)
            .all()
        )
        if db_courses:
            courses = [
                {
                    "id": c.id,
                    "course_code": c.course_code,
                    "course_title": c.course_title,
                    "credits": c.credits,
                    "term": c.term,
                    "grade": c.grade,
                    "confidence": c.confidence,
                }
                for c in db_courses
            ]
            needs_review = any((c.confidence or 0) < 0.7 for c in db_courses) or not db_courses
        else:
            # No rows yet — fall back to live parse (first-time or failed save)
            raw_courses = parse_transcript_text(transcript.raw_text or "")
            courses = [
                {
                    "id": -1,
                    "course_code": c.course_code,
                    "course_title": c.course_title,
                    "credits": c.credits,
                    "term": c.term,
                    "grade": c.grade,
                    "confidence": c.confidence,
                }
                for c in raw_courses
            ]
            needs_review = any((c.confidence or 0) < 0.7 for c in raw_courses) or not raw_courses
    else:
        # Fallback: for any other status (e.g. "received" from old CSV uploads),
        # return whatever TranscriptCourse rows exist in the DB.
        db_courses = (
            db.query(TranscriptCourse)
            .filter(TranscriptCourse.transcript_id == transcript.id)
            .all()
        )
        if db_courses:
            courses = [
                {
                    "id": c.id,
                    "course_code": c.course_code,
                    "course_title": c.course_title,
                    "credits": c.credits,
                    "term": c.term,
                    "grade": c.grade,
                    "confidence": c.confidence,
                }
                for c in db_courses
            ]

    return {
        "student_id": student_id,
        "transcript_id": transcript.id,
        "status": transcript.status,
        "courses": courses,
        "needs_review": needs_review,
    }


def create_transcript_stub(db: Session, student_id: int, filename: str | None) -> Transcript:
    transcript = Transcript(student_id=student_id, filename=filename)
    db.add(transcript)
    db.commit()
    db.refresh(transcript)
    return transcript


def create_transcript_with_csv(
    db: Session,
    student_id: int,
    filename: str | None,
    content: str,
) -> Transcript:
    transcript = Transcript(student_id=student_id, filename=filename, status="confirmed")
    db.add(transcript)
    db.commit()
    db.refresh(transcript)

    courses = parse_transcript_csv(content)
    for course in courses:
        db.add(
            TranscriptCourse(
                transcript_id=transcript.id,
                course_code=course.course_code,
                course_title=course.course_title,
                credits=course.credits,
                term=course.term,
                grade=course.grade,
            )
        )
        _upsert_course(db, course.course_code, course.course_title, course.credits)
    db.commit()
    return transcript


def create_transcript_with_pdf(
    db: Session,
    student_id: int,
    filename: str | None,
    data: bytes,
) -> Transcript:
    raw_text = extract_text_from_pdf(data)
    status = "parsed_raw" if raw_text else "received"
    transcript = Transcript(
        student_id=student_id,
        filename=filename,
        raw_text=raw_text,
        status=status,
    )
    db.add(transcript)
    db.commit()
    db.refresh(transcript)

    if raw_text:
        courses = parse_transcript_text(raw_text)
        for course in courses:
            db.add(
                TranscriptCourse(
                    transcript_id=transcript.id,
                    course_code=course.course_code,
                    course_title=course.course_title,
                    credits=course.credits,
                    term=course.term,
                    grade=course.grade,
                    confidence=course.confidence,
                )
            )
            _upsert_course(db, course.course_code, course.course_title, course.credits)
        db.commit()
    return transcript


def get_parse_preview_for_document(db: Session, document_id: int) -> dict:
    """Re-parse a DocumentUpload and return structured preview without writing to DB."""
    doc = db.get(DocumentUpload, document_id)
    if doc is None:
        raise HTTPException(status_code=404, detail="Document not found.")

    raw_text = doc.raw_text or ""
    notes: list[str] = []
    detected: list[dict] = []

    if doc.kind in ("transcript", "degree_audit"):
        if not raw_text:
            notes.append("No text could be extracted from this document. Try a different PDF.")
        else:
            courses = parse_transcript_text(raw_text)
            low_conf = [c for c in courses if (c.confidence or 0) < 0.7]
            if low_conf:
                notes.append(
                    f"{len(low_conf)} course(s) have low confidence — please review them carefully."
                )
            if not courses:
                notes.append("No courses were detected. The format may not be supported.")
            detected = [
                {
                    "course_code": c.course_code,
                    "course_title": c.course_title,
                    "term": c.term,
                    "credits": c.credits,
                    "grade": c.grade,
                    "confidence": c.confidence or 0.4,
                }
                for c in courses
            ]
    else:
        notes.append(f"Document kind '{doc.kind}' does not support course extraction.")

    return {
        "document_id": document_id,
        "detected_courses": detected,
        "notes": notes,
        "needs_review": bool([n for n in notes if "low confidence" in n or "No courses" in n]),
    }


def confirm_transcript(
    db: Session,
    payload: TranscriptConfirmRequest,
) -> dict:
    """Save user-confirmed (and optionally edited) courses as the canonical transcript."""
    transcript = (
        db.query(Transcript)
        .filter(Transcript.student_id == payload.student_id)
        .order_by(Transcript.uploaded_at.desc())
        .first()
    )
    if transcript is None:
        transcript = Transcript(
            student_id=payload.student_id,
            filename="manual",
            status="confirmed",
        )
        db.add(transcript)
        db.flush()

    # Replace existing courses with user-confirmed set
    db.query(TranscriptCourse).filter(
        TranscriptCourse.transcript_id == transcript.id
    ).delete(synchronize_session=False)

    for c in payload.courses:
        db.add(
            TranscriptCourse(
                transcript_id=transcript.id,
                course_code=c.course_code,
                course_title=c.course_title,
                credits=c.credits,
                term=c.term,
                grade=c.grade,
                confidence=None,  # null means user-confirmed
            )
        )
        _upsert_course(db, c.course_code, c.course_title, c.credits)

    transcript.status = "confirmed"
    db.commit()
    return {
        "transcript_id": transcript.id,
        "student_id": payload.student_id,
        "status": "confirmed",
        "course_count": len(payload.courses),
    }


def _upsert_course(
    db: Session,
    code: str,
    title: str | None,
    credits: int | None,
):
    existing = db.query(Course).filter(Course.code == code).first()
    if existing:
        if title and not existing.title:
            existing.title = title
        if credits and not existing.credits:
            existing.credits = credits
        db.add(existing)
        return existing
    course = Course(code=code, title=title, credits=credits)
    db.add(course)
    return course
