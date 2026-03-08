from app.core.database import SessionLocal
from app.models.transcript import Transcript, TranscriptCourse
from app.models.prerequisite import Prerequisite
from app.models.course import Course
from app.services.graph import build_graph, topo_sort

db = SessionLocal()

prereq_map = {}
for row in db.query(Prerequisite).all():
    if row.relation == "required":
        prereq_map.setdefault(row.course_code, set()).add(row.prereq_code)
graph = build_graph(prereq_map)
ordered = topo_sort(graph)
print("Ordered courses for planning:", len(ordered))

t12 = (
    db.query(Transcript)
    .filter(Transcript.student_id == 13)
    .order_by(Transcript.uploaded_at.desc())
    .first()
)
completed = {
    c.course_code
    for c in db.query(TranscriptCourse)
    .filter(TranscriptCourse.transcript_id == t12.id)
    .all()
}
print("Completed+WIP courses:", len(completed))

remaining = [c for c in ordered if c not in completed]
print("Remaining courses:", len(remaining))
for c in remaining:
    course = db.query(Course).filter(Course.code == c).first()
    print(f"  {c}: {course.title if course else '?'} ({course.credits if course else '?'} cr)")

db.close()
