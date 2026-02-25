from datetime import datetime

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.models.student import Student
from app.models.transcript import Transcript, TranscriptCourse
from app.schemas.student import StudentCreateRequest, StudentUpdateRequest


def create_student(db: Session, payload: StudentCreateRequest) -> Student:
    # Deduplicate by school-issued student_id when provided.
    # Prefer the record that already has transcript data; fall back to lowest id.
    if payload.student_id:
        candidates = (
            db.query(Student)
            .filter(Student.student_id == payload.student_id)
            .order_by(Student.id)
            .all()
        )
        if candidates:
            # Pick the candidate whose student_id has the most transcript courses
            best = candidates[0]
            best_count = (
                db.query(TranscriptCourse)
                .join(Transcript, TranscriptCourse.transcript_id == Transcript.id)
                .filter(Transcript.student_id == best.id)
                .count()
            )
            for candidate in candidates[1:]:
                count = (
                    db.query(TranscriptCourse)
                    .join(Transcript, TranscriptCourse.transcript_id == Transcript.id)
                    .filter(Transcript.student_id == candidate.id)
                    .count()
                )
                if count > best_count:
                    best = candidate
                    best_count = count
            # Update preferences on the best record
            for field, value in payload.model_dump(exclude_none=True).items():
                setattr(best, field, value)
            db.commit()
            db.refresh(best)
            return best
    student = Student(**payload.model_dump())
    db.add(student)
    db.commit()
    db.refresh(student)
    return student


def get_student(db: Session, student_id: int) -> Student:
    student = db.get(Student, student_id)
    if student is None:
        raise HTTPException(status_code=404, detail="Student not found.")
    return student


def update_student(db: Session, student_id: int, payload: StudentUpdateRequest) -> Student:
    student = db.get(Student, student_id)
    if student is None:
        raise HTTPException(status_code=404, detail="Student not found.")
    for field, value in payload.model_dump(exclude_none=True).items():
        setattr(student, field, value)
    student.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(student)
    return student


def calculate_gpa(db: Session, student_id: int) -> tuple[float | None, int]:
    # Use only the most recent transcript to avoid counting duplicate courses
    # from previous uploads.
    latest = (
        db.query(Transcript)
        .filter(Transcript.student_id == student_id)
        .order_by(Transcript.uploaded_at.desc())
        .first()
    )
    if latest is None:
        return None, 0
    courses = (
        db.query(TranscriptCourse)
        .filter(TranscriptCourse.transcript_id == latest.id)
        .all()
    )
    if not courses:
        return None, 0

    total_points = 0.0
    total_credits = 0
    for course in courses:
        if not course.credits or not course.grade:
            continue
        points = _grade_points(course.grade)
        if points is None:
            continue
        total_points += points * course.credits
        total_credits += course.credits

    if total_credits == 0:
        return None, 0
    return round(total_points / total_credits, 2), total_credits


def _grade_points(grade: str) -> float | None:
    normalized = grade.strip().upper()
    scale = {
        "A+": 4.0,
        "A": 4.0,
        "A-": 3.7,
        "B+": 3.3,
        "B": 3.0,
        "B-": 2.7,
        "C+": 2.3,
        "C": 2.0,
        "C-": 1.7,
        "D+": 1.3,
        "D": 1.0,
        "D-": 0.7,
        "F": 0.0,
    }
    return scale.get(normalized)
