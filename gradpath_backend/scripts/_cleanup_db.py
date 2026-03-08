"""
One-time DB cleanup: collapse duplicate student records for school_id=104778.
Keeps the earliest record that has a full 49-course transcript (id=4),
deletes every other duplicate along with all their plans and transcripts.
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from app.core.database import SessionLocal
from app.models.student import Student
from app.models.transcript import Transcript, TranscriptCourse
from app.models.plan import Plan, PlanTerm, PlanItem
from app.models.risk import Risk

db = SessionLocal()

KEEP_ID = 4   # Immanuella 104778, 49 courses — canonical record

# ── 1. Find all 104778 duplicates we want to remove ───────────────────────────
to_delete = (
    db.query(Student)
    .filter(Student.student_id == "104778", Student.id != KEEP_ID)
    .all()
)
delete_ids = [s.id for s in to_delete]
print("Deleting student ids:", delete_ids)

# ── 2. Delete plans (plan_items → plan_terms → plans → risks) ─────────────────
for sid in delete_ids:
    plans = db.query(Plan).filter(Plan.student_id == sid).all()
    for plan in plans:
        terms = db.query(PlanTerm).filter(PlanTerm.plan_id == plan.id).all()
        for term in terms:
            db.query(PlanItem).filter(PlanItem.term_id == term.id).delete()
        db.query(PlanTerm).filter(PlanTerm.plan_id == plan.id).delete()
        db.query(Risk).filter(Risk.plan_id == plan.id).delete()
        db.delete(plan)
db.flush()
print("  Plans cleaned.")

# ── 3. Also wipe the plans for KEEP_ID so we start fresh ─────────────────────
for plan in db.query(Plan).filter(Plan.student_id == KEEP_ID).all():
    for term in db.query(PlanTerm).filter(PlanTerm.plan_id == plan.id).all():
        db.query(PlanItem).filter(PlanItem.term_id == term.id).delete()
    db.query(PlanTerm).filter(PlanTerm.plan_id == plan.id).delete()
    db.query(Risk).filter(Risk.plan_id == plan.id).delete()
    db.delete(plan)
db.flush()

# ── 4. Delete transcripts for the duplicates ──────────────────────────────────
for sid in delete_ids:
    for tx in db.query(Transcript).filter(Transcript.student_id == sid).all():
        db.query(TranscriptCourse).filter(TranscriptCourse.transcript_id == tx.id).delete()
        db.delete(tx)
db.flush()   # must flush transcript deletes before student rows can be removed
print("  Transcripts cleaned.")

# ── 5. Delete the duplicate student rows ──────────────────────────────────────
for s in to_delete:
    db.delete(s)
db.flush()
db.commit()
print("  Student duplicates removed.")

# ── 6. Summary ────────────────────────────────────────────────────────────────
print("\n=== Remaining students ===")
for s in db.query(Student).order_by(Student.id).all():
    txs = db.query(Transcript).filter(Transcript.student_id == s.id).all()
    courses = sum(
        db.query(TranscriptCourse).filter(TranscriptCourse.transcript_id == t.id).count()
        for t in txs
    )
    plans = db.query(Plan).filter(Plan.student_id == s.id).count()
    print("  id=%2d school=%-8s %-22s | tx=%d courses=%d plans=%d" % (
        s.id, str(s.student_id), s.first_name + " " + s.last_name, len(txs), courses, plans
    ))

db.close()
print("\nDone. Re-run onboarding or hit Re-optimize to generate a fresh plan.")
