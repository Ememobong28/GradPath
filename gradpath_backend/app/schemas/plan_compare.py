from pydantic import BaseModel


class PlanCompareResponse(BaseModel):
    baseline_plan_id: int
    simulated_plan_id: int
    term_count_diff: int
    added_courses: list[str]
    removed_courses: list[str]
