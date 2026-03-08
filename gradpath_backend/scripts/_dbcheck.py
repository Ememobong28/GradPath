import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from app.core.database import SessionLocal
from app.models.student import Student
from app.models.transcript import Transcript, TranscriptCourse
from app.models.plan import Plan, PlanItem

db = SessionLocal()
students = db.query(Student).all()
for s in students:
    txs = db.query(Transcript).filter(Transcript.student_id == s.id).all()
    total_courses = sum(
        db.query(TranscriptCourse).filter(TranscriptCourse.transcript_id == t.id).count()
        for t in txs
    )
    plans = db.query(Plan).filter(Plan.student_id == s.id).count()
    print("Student DB_id=%d school_id=%s name=%s %s | transcripts=%d courses=%d plans=%d" % (
        s.id, s.student_id, s.first_name, s.last_name, len(txs), total_courses, plans
    ))

# Show latest plan's start
latest = db.query(Plan).order_by(Plan.id.desc()).first()
if latest:
    from app.models.plan import PlanTerm
    terms = db.query(PlanTerm).filter(PlanTerm.plan_id == latest.id).order_by(PlanTerm.id).all()
    print("\nLatest plan id=%d student_id=%d, terms=%d" % (latest.id, latest.student_id, len(terms)))
    for t in terms[:3]:
        items = db.query(PlanItem).filter(PlanItem.term_id == t.id).count()
        print("  %s  (%d items)" % (t.term_name, items))
    if len(terms) > 3:
        print("  ...")
        last = terms[-1]
        items = db.query(PlanItem).filter(PlanItem.term_id == last.id).count()
        print("  %s  (%d items) [last]" % (last.term_name, items))

db.close()
