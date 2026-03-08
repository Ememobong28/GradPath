import sys
sys.path.insert(0, "/Users/immanuellaumoren/Desktop/GradPath/gradpath_backend")
from app.core.database import SessionLocal
from app.models.student import Student
from app.models.transcript import Transcript, TranscriptCourse
db = SessionLocal()
print("id | name | student_id_field | transcripts")
for s in db.query(Student).all():
    tcount = db.query(TranscriptCourse).join(Transcript).filter(Transcript.student_id == s.id).count()
    print(str(s.id), "|", s.first_name, s.last_name, "|", repr(s.student_id), "|", tcount)
db.close()
