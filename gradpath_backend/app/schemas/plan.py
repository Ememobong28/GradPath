from pydantic import BaseModel, Field


class PlanGenerateRequest(BaseModel):
    student_id: int
    # Optional per-request overrides — if omitted, student profile values are used
    max_credits: int | None = Field(None, ge=6, le=30)
    summer_ok: bool | None = None
    target_grad_term: str | None = None
    major: str | None = None


class SemesterOut(BaseModel):
    term: str
    credits: int
    courses: list[str]


class PlanGenerateResponse(BaseModel):
    student_id: int
    status: str
    message: str
    plan_id: int | None = None
    semesters: list[SemesterOut] = []
    risk_summary: list[str] = []
