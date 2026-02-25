from sqlalchemy.orm import Session

from app.models.prerequisite import Prerequisite
from app.schemas.prerequisite import PrerequisiteCreate


def bulk_create_prereqs(
    db: Session, prereqs: list[PrerequisiteCreate]
) -> list[Prerequisite]:
    items = [Prerequisite(**item.model_dump()) for item in prereqs]
    db.add_all(items)
    db.commit()
    for item in items:
        db.refresh(item)
    return items
