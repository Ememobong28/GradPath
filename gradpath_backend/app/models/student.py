from datetime import datetime

from sqlalchemy import Boolean, Column, DateTime, ForeignKey, Integer, String

from app.models.base import Base


class Student(Base):
    __tablename__ = "students"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=True, index=True)
    first_name = Column(String, nullable=False)
    last_name = Column(String, nullable=False)
    school = Column(String, nullable=True)
    student_id = Column(String, nullable=True)
    honors = Column(Boolean, default=False)
    max_credits = Column(Integer, default=15)
    summer_ok = Column(Boolean, default=True)
    target_grad_term = Column(String, nullable=True)
    major = Column(String, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
