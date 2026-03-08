import sys
sys.path.insert(0, "/Users/immanuellaumoren/Desktop/GradPath/gradpath_backend")

from app.core.database import SessionLocal
from app.models.plan import Plan, PlanTerm, PlanItem
from app.models.transcript import Transcript, TranscriptCourse
from app.models.student import Student

db = SessionLocal()

print("=== STUDENTS ===")
for s in db.query(Student).all():
    print(f"  id={s.id} name={s.first_name} {s.last_name}")

print()
print("=== TRANSCRIPTS ===")
for t in db.query(Transcript).all():
    count = db.query(TranscriptCourse).filter(TranscriptCourse.transcript_id == t.id).count()
    print(f"  id={t.id} student_id={t.student_id} status={t.status} courses={count} uploaded={t.uploaded_at}")

print()
print("=== ALL PLANS ===")
for plan in db.query(Plan).order_by(Plan.id.desc()).all():
    term_count = db.query(PlanTerm).filter(PlanTerm.plan_id == plan.id).count()
    completed = {
        c.course_code
        for c in db.query(TranscriptCourse)
        .join(Transcript, TranscriptCourse.transcript_id == Transcript.id)
        .filter(Transcript.student_id == plan.student_id)
        .all()
        if c.course_code
    }
    print(f"  plan id={plan.id} student_id={plan.student_id} status={plan.status} terms={term_count} transcript_courses_at_time={len(completed)}")
    first_term = db.query(PlanTerm).filter(PlanTerm.plan_id == plan.id).order_by(PlanTerm.id).first()
    if first_term:
        items = db.query(PlanItem).filter(PlanItem.term_id == first_term.id).all()
        print(f"    First term: {first_term.term_name}")
        for item in items:
            already_done = item.course_code in completed
            print(f"      {item.course_code:12} title={item.course_title!r:30} already_completed={already_done}")

db.close()
