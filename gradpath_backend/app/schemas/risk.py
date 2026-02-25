from pydantic import BaseModel


class RiskResponse(BaseModel):
    id: int
    plan_id: int
    kind: str
    message: str

    model_config = {
        "from_attributes": True,
    }
