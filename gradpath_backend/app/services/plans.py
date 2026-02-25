from sqlalchemy.orm import Session, joinedload

from app.models.plan import Plan, PlanTerm, PlanItem
from app.models.course import Course
from app.models.risk import Risk


def get_plan(db: Session, plan_id: int) -> Plan | None:
    plan = (
        db.query(Plan)
        .options(joinedload(Plan.terms).joinedload(PlanTerm.items))
        .filter(Plan.id == plan_id)
        .first()
    )
    if plan is None:
        return None

    # Collect all course codes that need enrichment
    all_codes = {
        item.course_code
        for term in plan.terms
        for item in term.items
        if item.course_code and (not item.course_title or item.credits is None)
    }
    if all_codes:
        course_map = {
            c.code: c
            for c in db.query(Course).filter(Course.code.in_(all_codes)).all()
        }
        for term in plan.terms:
            for item in term.items:
                if item.course_code in course_map:
                    c = course_map[item.course_code]
                    if not item.course_title and c.title:
                        item.course_title = c.title
                    if item.credits is None and c.credits:
                        item.credits = c.credits

    return plan


def get_plan_risks(db: Session, plan_id: int) -> list[Risk]:
    return db.query(Risk).filter(Risk.plan_id == plan_id).all()


def compare_plans(db: Session, baseline_id: int, simulated_id: int):
    baseline = get_plan(db, baseline_id)
    simulated = get_plan(db, simulated_id)
    if baseline is None or simulated is None:
        return None

    baseline_courses = {
        item.course_code
        for term in baseline.terms
        for item in term.items
        if item.course_code
    }
    simulated_courses = {
        item.course_code
        for term in simulated.terms
        for item in term.items
        if item.course_code
    }

    return {
        "baseline_plan_id": baseline_id,
        "simulated_plan_id": simulated_id,
        "term_count_diff": len(simulated.terms) - len(baseline.terms),
        "added_courses": sorted(simulated_courses - baseline_courses),
        "removed_courses": sorted(baseline_courses - simulated_courses),
    }
