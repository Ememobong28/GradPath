import sys, os, requests, json
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from app.core.database import SessionLocal
from app.models.student import Student
from app.models.plan import Plan, PlanTerm, PlanItem
from app.models.transcript import Transcript, TranscriptCourse

db = SessionLocal()
students = db.query(Student).all()
for s in students:
    tc = db.query(TranscriptCourse).join(Transcript, TranscriptCourse.transcript_id == Transcript.id).filter(Transcript.student_id == s.id).count()
    plans = db.query(Plan).filter(Plan.student_id == s.id).order_by(Plan.id.desc()).all()
    latest = plans[0] if plans else None
    print("student id=%d school_id=%s transcript_courses=%d plans=%d" % (s.id, s.student_id, tc, len(plans)))
    if latest:
        terms = db.query(PlanTerm).filter(PlanTerm.plan_id == latest.id).all()
        items_total = sum(db.query(PlanItem).filter(PlanItem.term_id == t.id).count() for t in terms)
        print("  latest plan id=%d terms=%d items=%d" % (latest.id, len(terms), items_total))
        if terms:
            t0 = terms[0]
            items = db.query(PlanItem).filter(PlanItem.term_id == t0.id).all()
            for i in items[:3]:
                print("    course=%s title=%s credits=%s" % (i.course_code, i.course_title, i.credits))

db.close()

# hit the API
r = requests.get("http://127.0.0.1:8000/api/plans/79")
if r.ok:
    d = r.json()
    print("\nAPI plan keys:", list(d.keys()))
    print("program_name:", d.get("program_name"))
    terms = d.get("terms", [])
    print("terms count:", len(terms))
    if terms:
        t = terms[0]
        print("term keys:", list(t.keys()))
        items = t.get("items", [])
        if items:
            print("item keys:", list(items[0].keys()))
            print("sample item:", items[0])
