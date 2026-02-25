from sqlalchemy import Column, Integer, String

from app.models.base import Base


class Program(Base):
    __tablename__ = "programs"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, nullable=False, index=True)
    catalog_year = Column(String, nullable=True)
    degree = Column(String, nullable=True)
