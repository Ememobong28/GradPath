"""
Full database reset — wipes ALL students, transcripts, plans, risks, documents.
Run once before a clean onboarding test.
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from app.core.database import SessionLocal
from app.models.student import Student
from app.models.transcript import Transcript, TranscriptCourse
from app.models.plan import Plan, PlanTerm, PlanItem
from app.models.risk import Risk
from app.models.document import DocumentUpload

db = SessionLocal()

# Delete in FK-safe order
print("Deleting plan items...")
db.query(PlanItem).delete()
print("Deleting plan terms...")
db.query(PlanTerm).delete()
print("Deleting risks...")
db.query(Risk).delete()
print("Deleting plans...")
db.query(Plan).delete()
print("Deleting transcript courses...")
db.query(TranscriptCourse).delete()
print("Deleting transcripts...")
db.query(Transcript).delete()
print("Deleting documents...")
try:
    db.query(DocumentUpload).delete()
except Exception as e:
    print("  (documents skip:", e, ")")
print("Deleting students...")
db.query(Student).delete()

db.commit()
db.close()
print("\nDone — database is clean. Ready for fresh onboarding.")
