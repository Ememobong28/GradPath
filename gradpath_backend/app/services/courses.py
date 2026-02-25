from sqlalchemy.orm import Session

from app.models.course import Course
from app.schemas.course import CourseCreate


def bulk_create_courses(db: Session, courses: list[CourseCreate]) -> list[Course]:
    items = [Course(**course.model_dump()) for course in courses]
    db.add_all(items)
    db.commit()
    for item in items:
        db.refresh(item)
    return items
