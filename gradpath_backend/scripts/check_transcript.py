from app.core.database import SessionLocal
from app.models.transcript import Transcript, TranscriptCourse

db = SessionLocal()
ts = db.query(Transcript).filter(Transcript.student_id == 12).all()
for t in ts:
    courses = db.query(TranscriptCourse).filter(TranscriptCourse.transcript_id == t.id).all()
    total = sum((c.credits or 3) for c in courses)
    print(f"transcript={t.id} courses={len(courses)} total_credits={total}")
    for c in courses[:3]:
        print(f"  {c.course_code} cr={c.credits} grade={c.grade}")

# Check transcript HTTP endpoint
import json, requests
r = requests.get("http://127.0.0.1:8000/api/transcripts/12")
print("HTTP /api/transcripts/12 status:", r.status_code)
if r.status_code == 200:
    data = r.json()
    print("keys:", list(data.keys()))
    courses = data.get("courses", [])
    print("courses count:", len(courses))
    if courses:
        print("first course:", courses[0])
db.close()
