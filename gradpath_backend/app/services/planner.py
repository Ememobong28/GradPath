from datetime import datetime

from sqlalchemy.orm import Session

from app.models.plan import Plan, PlanTerm, PlanItem
from app.models.student import Student
from app.models.course import Course
from app.models.transcript import Transcript, TranscriptCourse
from app.models.prerequisite import Prerequisite
from app.models.risk import Risk
from app.schemas.plan import PlanGenerateRequest, PlanGenerateResponse, SemesterOut
from app.services.graph import build_graph, topo_sort
from app.services.scheduler import CourseOffering, schedule_terms


def generate_plan(db: Session, payload: PlanGenerateRequest) -> PlanGenerateResponse:
    plan = Plan(student_id=payload.student_id, status="queued")
    db.add(plan)
    db.commit()
    db.refresh(plan)
    student = db.get(Student, payload.student_id)
    # Per-request overrides take precedence over stored student preferences
    max_credits = payload.max_credits if payload.max_credits is not None else (student.max_credits if student else 15)
    allow_summer = payload.summer_ok if payload.summer_ok is not None else (student.summer_ok if student else True)
    honors_flag = student.honors if student else False

    # ── Find all DB student records that share the same school student_id ──
    # This guards against the Flutter app caching a stale DB id; any duplicate
    # records for the same school student will have their transcript courses merged.
    if student and student.student_id:
        sibling_ids = [
            s.id
            for s in db.query(Student)
            .filter(Student.student_id == student.student_id)
            .all()
        ]
    else:
        sibling_ids = [payload.student_id]

    completed_courses = {
        c.course_code
        for c in db.query(TranscriptCourse)
        .join(Transcript, TranscriptCourse.transcript_id == Transcript.id)
        .filter(Transcript.student_id.in_(sibling_ids))
        .all()
        if c.course_code
    }

    offerings: dict[str, CourseOffering] = {}
    for course in db.query(Course).all():
        availability = {"Fall", "Spring", "Summer"}
        if course.availability:
            availability = {s.strip() for s in course.availability.split(",")}
        offerings[course.code] = CourseOffering(
            code=course.code,
            credits=course.credits or 3,
            availability=availability,
            honors_only=course.honors_only or False,
        )

    prereq_map = {code: set() for code in offerings.keys()}
    coreq_map: dict[str, set[str]] = {}
    optional_map: dict[str, set[str]] = {}
    for row in db.query(Prerequisite).all():
        if row.relation == "required":
            prereq_map.setdefault(row.course_code, set()).add(row.prereq_code)
        elif row.relation == "coreq":
            coreq_map.setdefault(row.course_code, set()).add(row.prereq_code)
        elif row.relation == "optional":
            optional_map.setdefault(row.course_code, set()).add(row.prereq_code)
    graph = build_graph(prereq_map)
    ordered_courses = topo_sort(graph)

    # Use sibling_ids to infer start term even if the active record has no transcript
    _start_term, _start_year = _infer_start_term(db, sibling_ids)

    # ── Graduation check ─────────────────────────────────────────────────────
    # If the inferred plan start is AFTER the student's target grad term, the
    # student completes their degree in their current in-progress semester.
    if student and student.target_grad_term and _start_term and _start_year:
        tgt = _parse_term_label(student.target_grad_term)
        _start_parsed = _parse_term_label(f"{_start_term} {_start_year}")
        if tgt and _start_parsed and (_start_parsed[1], _start_parsed[2]) > (tgt[1], tgt[2]):
            plan.status = "complete"
            db.commit()
            return PlanGenerateResponse(
                student_id=payload.student_id,
                status="complete",
                message="Student completes degree in current semester.",
                plan_id=plan.id,
                semesters=[],
                risk_summary=[],
            )

    schedule = schedule_terms(
        ordered_courses=ordered_courses,
        offerings=offerings,
        prereqs=prereq_map,
        coreqs=coreq_map,
        optional_prereqs=optional_map,
        completed=completed_courses,
        max_credits=max_credits,
        allow_summer=allow_summer,
        honors_only=honors_flag,
        start_year=_start_year,
        start_term=_start_term,
    )

    for term in schedule.terms:
        term_row = PlanTerm(
            plan_id=plan.id,
            term_name=term["term"],
            credits=term["credits"],
        )
        db.add(term_row)
        db.flush()
        for course_code in term["courses"]:
            co = offerings.get(course_code)
            course_obj = db.query(Course).filter(Course.code == course_code).first()
            db.add(PlanItem(
                term_id=term_row.id,
                course_code=course_code,
                course_title=course_obj.title if course_obj else None,
                credits=co.credits if co else (course_obj.credits if course_obj else None),
            ))
    db.commit()

    message = "Plan generated successfully."
    if schedule.bottlenecks:
        message = f"Plan generated with {len(schedule.bottlenecks)} warning(s)."
        for item in schedule.bottlenecks:
            db.add(Risk(plan_id=plan.id, kind="bottleneck", message=item))
        db.commit()

    plan.status = "complete"
    db.commit()

    return PlanGenerateResponse(
        student_id=payload.student_id,
        status="complete",
        message=message,
        plan_id=plan.id,
        semesters=[SemesterOut(**t) for t in schedule.terms],
        risk_summary=schedule.bottlenecks,
    )


def _infer_start_term(db: Session, student_ids: list[int]) -> tuple[str | None, int | None]:
    terms = (
        db.query(TranscriptCourse.term)
        .join(Transcript, TranscriptCourse.transcript_id == Transcript.id)
        .filter(Transcript.student_id.in_(student_ids))
        .all()
    )
    parsed = [_parse_term_label(t[0]) for t in terms if t and t[0]]
    parsed = [p for p in parsed if p]
    if not parsed:
        now = datetime.now()
        return "Fall", now.year
    # Use the LATEST transcript term and advance to the next planning term
    parsed.sort(key=lambda p: (p[1], p[2]))
    term, year, _ = parsed[-1]  # last completed / WIP term
    # Advance to the next semester
    if term == "Fall":
        return "Spring", year + 1
    elif term == "Spring":
        return "Fall", year
    else:  # Summer
        return "Fall", year


def _parse_term_label(label: str) -> tuple[str, int, int] | None:
    parts = label.strip().split()
    if len(parts) < 2:
        return None
    term = parts[0].title()
    year = None
    for part in reversed(parts):
        if part.isdigit() and len(part) == 4:
            year = int(part)
            break
    if year is None:
        return None
    order = {"Spring": 1, "Summer": 2, "Fall": 3, "Winter": 4}.get(term, 5)
    return term, year, order
