from datetime import datetime

from sqlalchemy import Column, DateTime, ForeignKey, Integer, String, Text

from app.models.base import Base


class DocumentUpload(Base):
    __tablename__ = "document_uploads"

    id = Column(Integer, primary_key=True, index=True)
    student_id = Column(Integer, ForeignKey("students.id"), nullable=False)
    kind = Column(String, nullable=False)  # transcript/audit/catalog
    filename = Column(String, nullable=True)
    raw_text = Column(Text, nullable=True)
    status = Column(String, default="received")
    uploaded_at = Column(DateTime, default=datetime.utcnow)
