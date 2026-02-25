from sqlalchemy.orm import Session

from app.models.plan import Plan, PlanTerm, PlanItem
from app.models.student import Student
from app.models.risk import Risk
from app.schemas.plan import PlanGenerateRequest
from app.schemas.simulate import SimulateRequest, SimulateResponse, SimulatedTerm, SimulatedItem
from app.services.planner import generate_plan


def simulate_plan(db: Session, payload: SimulateRequest) -> SimulateResponse:
    plan_row = db.get(Plan, payload.plan_id)
    if plan_row is None:
        return SimulateResponse(
            plan_id=payload.plan_id,
            status="error",
            message="Plan not found",
        )

    student = db.get(Student, plan_row.student_id)
    if student is None:
        return SimulateResponse(
            plan_id=payload.plan_id,
            status="error",
            message="Student not found",
        )

    original_max = student.max_credits
    original_summer = student.summer_ok

    if payload.max_credits is not None:
        student.max_credits = payload.max_credits
    if payload.summer_ok is not None:
        student.summer_ok = payload.summer_ok
    db.commit()

    plan = generate_plan(db, PlanGenerateRequest(student_id=plan_row.student_id))

    # Restore original settings
    student.max_credits = original_max
    student.summer_ok = original_summer
    db.commit()

    # ── Build rich response from the newly generated plan ──────────────────
    sim_plan_id = plan.plan_id

    # Fetch terms with their items (ordered by id for chronological order)
    term_rows = (
        db.query(PlanTerm)
        .filter(PlanTerm.plan_id == sim_plan_id)
        .order_by(PlanTerm.id)
        .all()
    )

    sim_terms: list[SimulatedTerm] = []
    for tr in term_rows:
        item_rows = (
            db.query(PlanItem)
            .filter(PlanItem.term_id == tr.id)
            .order_by(PlanItem.id)
            .all()
        )
        items = [
            SimulatedItem(
                id=ir.id,
                term_id=ir.term_id,
                course_code=ir.course_code,
                course_title=ir.course_title,
                credits=ir.credits,
            )
            for ir in item_rows
        ]
        sim_terms.append(
            SimulatedTerm(
                id=tr.id,
                plan_id=tr.plan_id,
                term_name=tr.term_name,
                credits=tr.credits,
                items=items,
            )
        )

    projected_graduation = sim_terms[-1].term_name if sim_terms else None

    # Derive a 0-100 risk score from bottleneck count (each adds ~15 pts, capped)
    risk_rows = db.query(Risk).filter(Risk.plan_id == sim_plan_id).all()
    risk_score = min(100, len(risk_rows) * 15)

    return SimulateResponse(
        plan_id=payload.plan_id,
        status="simulated",
        message=f"Simulation complete: {plan.message}",
        sim_plan_id=sim_plan_id,
        projected_graduation=projected_graduation,
        risk_score=risk_score,
        terms=sim_terms,
    )
