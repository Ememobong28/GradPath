from datetime import datetime

from pydantic import BaseModel


class DocumentUploadResponse(BaseModel):
    id: int
    student_id: int
    kind: str
    filename: str | None = None
    status: str
    uploaded_at: datetime

    model_config = {"from_attributes": True}
