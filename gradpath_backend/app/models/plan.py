from datetime import datetime

from sqlalchemy import Column, DateTime, ForeignKey, Integer, String
from sqlalchemy.orm import relationship

from app.models.base import Base
from app.models.risk import Risk


class Plan(Base):
    __tablename__ = "plans"

    id = Column(Integer, primary_key=True, index=True)
    student_id = Column(Integer, ForeignKey("students.id"), nullable=False)
    status = Column(String, default="queued")
    created_at = Column(DateTime, default=datetime.utcnow)

    terms = relationship("PlanTerm", back_populates="plan")
    risks = relationship("Risk", backref="plan")


class PlanTerm(Base):
    __tablename__ = "plan_terms"

    id = Column(Integer, primary_key=True, index=True)
    plan_id = Column(Integer, ForeignKey("plans.id"), nullable=False)
    term_name = Column(String, nullable=False)
    credits = Column(Integer, default=0)

    plan = relationship("Plan", back_populates="terms")
    items = relationship("PlanItem", back_populates="term")


class PlanItem(Base):
    __tablename__ = "plan_items"

    id = Column(Integer, primary_key=True, index=True)
    term_id = Column(Integer, ForeignKey("plan_terms.id"), nullable=False)
    course_code = Column(String, nullable=False)
    course_title = Column(String, nullable=True)
    credits = Column(Integer, nullable=True)

    term = relationship("PlanTerm", back_populates="items")
