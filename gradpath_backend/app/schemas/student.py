from datetime import datetime

from pydantic import BaseModel, Field


class StudentCreateRequest(BaseModel):
    first_name: str = Field(..., min_length=1)
    last_name: str = Field(..., min_length=1)
    school: str | None = None
    student_id: str | None = None
    honors: bool = False
    max_credits: int = Field(15, ge=6, le=30)
    summer_ok: bool = True
    target_grad_term: str | None = None
    major: str | None = None


class StudentUpdateRequest(BaseModel):
    """All fields optional — only provided fields are written."""

    first_name: str | None = Field(None, min_length=1)
    last_name: str | None = Field(None, min_length=1)
    school: str | None = None
    student_id: str | None = None
    honors: bool | None = None
    max_credits: int | None = Field(None, ge=6, le=30)
    summer_ok: bool | None = None
    target_grad_term: str | None = None
    major: str | None = None


class StudentResponse(StudentCreateRequest):
    id: int
    created_at: datetime | None = None
    updated_at: datetime | None = None

    model_config = {"from_attributes": True}


class StudentResumeResponse(StudentResponse):
    """Extended response for the resume-where-you-left-off flow."""

    transcript_id: int | None = None
    transcript_status: str | None = None  # received / parsed_raw / confirmed
    plan_id: int | None = None            # latest generated plan for this student
