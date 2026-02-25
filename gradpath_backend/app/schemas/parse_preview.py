from pydantic import BaseModel


class ParsePreviewResponse(BaseModel):
    """Raw text preview (used by POST /documents/preview)."""

    text_excerpt: str
    length: int


class DetectedCourse(BaseModel):
    course_code: str
    course_title: str | None = None
    term: str | None = None
    credits: int | None = None
    grade: str | None = None
    confidence: float


class DocumentParsePreview(BaseModel):
    """Structured parse result returned by GET /documents/{id}/parse."""

    document_id: int
    detected_courses: list[DetectedCourse]
    notes: list[str]
    needs_review: bool
