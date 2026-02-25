from pydantic import BaseModel


class SimulateRequest(BaseModel):
    plan_id: int
    max_credits: int | None = None
    summer_ok: bool | None = None


class SimulatedItem(BaseModel):
    id: int
    term_id: int
    course_code: str | None = None
    course_title: str | None = None
    credits: int | None = None

    model_config = {"from_attributes": True}


class SimulatedTerm(BaseModel):
    id: int
    plan_id: int
    term_name: str
    credits: int | None = None
    items: list[SimulatedItem] = []

    model_config = {"from_attributes": True}


class SimulateResponse(BaseModel):
    # Original plan reference
    plan_id: int
    status: str
    message: str

    # Simulated plan detail (populated on success)
    sim_plan_id: int | None = None
    projected_graduation: str | None = None
    risk_score: int = 0          # 0‑100 integer percentage
    terms: list[SimulatedTerm] = []
