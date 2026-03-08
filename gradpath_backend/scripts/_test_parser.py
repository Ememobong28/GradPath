from pypdf import PdfReader
from app.services.transcript_parser import parse_transcript_text

path = "/Users/immanuellaumoren/Desktop/GradPath/Immanuella Umoren's Official Transcript .pdf"
reader = PdfReader(path)
text = "\n".join(page.extract_text() or "" for page in reader.pages)

courses = parse_transcript_text(text)

print(f"Total courses: {len(courses)}\n")
print(f"{'CODE':<12} {'TITLE':<45} {'TERM':<18} {'CR':>3} {'GRADE':<6} {'CONF'}")
print("-" * 100)
for c in courses:
    term  = c.term or "?"
    cr    = str(c.credits) if c.credits is not None else "?"
    grade = c.grade or "?"
    print(f"{c.course_code:<12} {(c.course_title or '')[:44]:<45} {term:<18} {cr:>3} {grade:<6} {c.confidence}")
