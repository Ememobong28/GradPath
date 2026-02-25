from datetime import datetime

from pydantic import BaseModel


class TranscriptUploadResponse(BaseModel):
    id: int
    student_id: int
    filename: str | None = None
    status: str
    uploaded_at: datetime

    model_config = {"from_attributes": True}


class TranscriptCourseOut(BaseModel):
    id: int
    course_code: str
    course_title: str | None = None
    credits: int | None = None
    term: str | None = None
    grade: str | None = None
    confidence: float | None = None

    model_config = {"from_attributes": True}


class ConfirmCourse(BaseModel):
    course_code: str
    course_title: str | None = None
    credits: int | None = None
    term: str | None = None
    grade: str | None = None


class TranscriptConfirmRequest(BaseModel):
    student_id: int
    courses: list[ConfirmCourse]


class TranscriptConfirmResponse(BaseModel):
    transcript_id: int
    student_id: int
    status: str
    course_count: int


class TranscriptStatusResponse(BaseModel):
    """GET /api/transcripts/{student_id} response."""

    student_id: int
    transcript_id: int | None = None
    # received | parsed_raw | confirmed
    status: str
    courses: list[TranscriptCourseOut] = []
    needs_review: bool = False
