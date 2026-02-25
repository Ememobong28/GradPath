from sqlalchemy import Column, Integer, String

from app.models.base import Base


class Prerequisite(Base):
    __tablename__ = "prerequisites"

    id = Column(Integer, primary_key=True, index=True)
    course_code = Column(String, nullable=False, index=True)
    prereq_code = Column(String, nullable=False, index=True)
    relation = Column(String, default="required")  # required/coreq/optional
