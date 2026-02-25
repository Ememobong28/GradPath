from pydantic import BaseModel


class PrerequisiteCreate(BaseModel):
    course_code: str
    prereq_code: str
    relation: str = "required"


class PrerequisiteCreateRequest(BaseModel):
    prerequisites: list[PrerequisiteCreate]


class PrerequisiteResponse(PrerequisiteCreate):
    id: int

    model_config = {
        "from_attributes": True,
    }
