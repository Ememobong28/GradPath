"""
Fix: student 13 graduates Spring 2026.
1. Update target_grad_term to 'Spring 2026'
2. Clear plan 81 terms (graduation = WIP semester, no future courses needed)
3. Update plan 81 total_credits to 0
"""
from app.core.database import SessionLocal
from app.models.student import Student
from app.models.plan import Plan, PlanTerm, PlanItem

db = SessionLocal()

# 1. Fix target_grad_term
student = db.query(Student).filter(Student.id == 13).first()
old_target = student.target_grad_term
student.target_grad_term = "Spring 2026"
print(f"target_grad_term: {old_target!r} → {student.target_grad_term!r}")

# 2. Clear plan 81 term items and terms
terms = db.query(PlanTerm).filter(PlanTerm.plan_id == 81).all()
print(f"Deleting {len(terms)} terms from plan 81")
for t in terms:
    items_deleted = db.query(PlanItem).filter(PlanItem.term_id == t.id).delete()
    print(f"  Deleted {items_deleted} items from {t.term_name}")
db.query(PlanTerm).filter(PlanTerm.plan_id == 81).delete()

# 3. Update plan
plan = db.query(Plan).filter(Plan.id == 81).first()
plan.status = "complete"
print(f"Plan 81: terms cleared, status=complete")

db.commit()
db.close()
print("Done.")
