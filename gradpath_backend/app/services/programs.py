from sqlalchemy.orm import Session

from app.models.program import Program
from app.models.requirement import Requirement, RequirementCourse
from app.schemas.program import ProgramCreateRequest
from app.schemas.requirement import RequirementCreate


def create_program(db: Session, payload: ProgramCreateRequest) -> Program:
    program = Program(**payload.model_dump())
    db.add(program)
    db.commit()
    db.refresh(program)
    return program


def add_requirements(
    db: Session, program_id: int, requirements: list[RequirementCreate]
) -> list[Requirement]:
    created: list[Requirement] = []
    for req in requirements:
        requirement = Requirement(
            program_id=program_id,
            name=req.name,
            kind=req.kind,
            credits_required=req.credits_required,
        )
        db.add(requirement)
        db.flush()
        for course in req.courses:
            db.add(RequirementCourse(requirement_id=requirement.id, course_code=course))
        created.append(requirement)
    db.commit()
    for item in created:
        db.refresh(item)
    return created
