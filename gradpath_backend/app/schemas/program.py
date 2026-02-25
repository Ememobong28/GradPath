from pydantic import BaseModel


class ProgramCreateRequest(BaseModel):
    name: str
    catalog_year: str | None = None
    degree: str | None = None


class ProgramResponse(ProgramCreateRequest):
    id: int

    model_config = {
        "from_attributes": True,
    }
