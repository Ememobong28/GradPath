from sqlalchemy import Boolean, Column, Integer, String

from app.models.base import Base


class Course(Base):
    __tablename__ = "courses"

    id = Column(Integer, primary_key=True, index=True)
    code = Column(String, nullable=False, index=True)
    title = Column(String, nullable=True)
    credits = Column(Integer, nullable=True)
    availability = Column(String, nullable=True)  # e.g., "Fall,Spring,Summer"
    honors_only = Column(Boolean, default=False)
