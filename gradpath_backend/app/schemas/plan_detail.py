from pydantic import BaseModel


class PlanItemResponse(BaseModel):
    id: int
    term_id: int
    course_code: str
    course_title: str | None = None
    credits: int | None = None

    model_config = {"from_attributes": True}


class PlanTermResponse(BaseModel):
    id: int
    plan_id: int
    term_name: str
    credits: int
    items: list[PlanItemResponse] = []

    model_config = {"from_attributes": True}


class PlanDetailResponse(BaseModel):
    id: int
    student_id: int
    status: str
    terms: list[PlanTermResponse] = []

    model_config = {"from_attributes": True}
