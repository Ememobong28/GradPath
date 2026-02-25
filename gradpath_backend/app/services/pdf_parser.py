from io import BytesIO
from typing import Iterable

from pypdf import PdfReader
from pypdf.errors import DependencyError, PdfReadError


def extract_text_from_pdf(data: bytes) -> str:
    try:
        reader = PdfReader(BytesIO(data))
    except (PdfReadError, DependencyError):
        return ""
    if reader.is_encrypted:
        try:
            reader.decrypt("")
        except Exception:
            return ""
    pages: Iterable[str] = []
    texts = []
    try:
        for page in reader.pages:
            text = page.extract_text() or ""
            texts.append(text)
    except (PdfReadError, DependencyError):
        return ""
    return "\n".join(texts).strip()
