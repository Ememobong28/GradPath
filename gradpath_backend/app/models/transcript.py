from datetime import datetime

from sqlalchemy import Column, DateTime, Float, ForeignKey, Integer, String, Text
from sqlalchemy.orm import relationship

from app.models.base import Base


class Transcript(Base):
    __tablename__ = "transcripts"

    id = Column(Integer, primary_key=True, index=True)
    student_id = Column(Integer, ForeignKey("students.id"), nullable=False)
    filename = Column(String, nullable=True)
    raw_text = Column(Text, nullable=True)
    status = Column(String, default="received")
    uploaded_at = Column(DateTime, default=datetime.utcnow)

    courses = relationship("TranscriptCourse", back_populates="transcript")


class TranscriptCourse(Base):
    __tablename__ = "transcript_courses"

    id = Column(Integer, primary_key=True, index=True)
    transcript_id = Column(Integer, ForeignKey("transcripts.id"), nullable=False)
    course_code = Column(String, nullable=False)
    course_title = Column(String, nullable=True)
    credits = Column(Integer, nullable=True)
    term = Column(String, nullable=True)
    grade = Column(String, nullable=True)
    confidence = Column(Float, nullable=True)  # 0.0–1.0; null means user-confirmed

    transcript = relationship("Transcript", back_populates="courses")
