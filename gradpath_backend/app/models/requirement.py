from sqlalchemy import Column, ForeignKey, Integer, String
from sqlalchemy.orm import relationship

from app.models.base import Base


class Requirement(Base):
    __tablename__ = "requirements"

    id = Column(Integer, primary_key=True, index=True)
    program_id = Column(Integer, ForeignKey("programs.id"), nullable=False)
    name = Column(String, nullable=False)
    kind = Column(String, nullable=False, default="core")  # core/elective/group
    credits_required = Column(Integer, nullable=True)

    program = relationship("Program", backref="requirements")


class RequirementCourse(Base):
    __tablename__ = "requirement_courses"

    id = Column(Integer, primary_key=True, index=True)
    requirement_id = Column(Integer, ForeignKey("requirements.id"), nullable=False)
    course_code = Column(String, nullable=False)

    requirement = relationship("Requirement", backref="courses")
