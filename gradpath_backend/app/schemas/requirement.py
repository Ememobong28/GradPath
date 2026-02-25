from pydantic import BaseModel


class RequirementCreate(BaseModel):
    name: str
    kind: str = "core"
    credits_required: int | None = None
    courses: list[str] = []


class RequirementCreateRequest(BaseModel):
    requirements: list[RequirementCreate]


class RequirementResponse(RequirementCreate):
    id: int
    program_id: int

    model_config = {
        "from_attributes": True,
    }
