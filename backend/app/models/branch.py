from sqlalchemy import Column, Integer, String
from app.database import Base


class Branch(Base):
    __tablename__ = "branches"

    id = Column(Integer, primary_key=True, autoincrement=True)
    name = Column(String(100), nullable=False, unique=True)
    display_name = Column(String(200), nullable=False)
    drive_file_id = Column(String(200), nullable=True)
