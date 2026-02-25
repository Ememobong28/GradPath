from pydantic import BaseModel


class CourseCreate(BaseModel):
    code: str
    title: str | None = None
    credits: int | None = None
    availability: str | None = None
    honors_only: bool = False


class CourseCreateRequest(BaseModel):
    courses: list[CourseCreate]


class CourseResponse(CourseCreate):
    id: int

    model_config = {
        "from_attributes": True,
    }
