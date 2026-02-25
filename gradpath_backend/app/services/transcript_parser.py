import csv
import re
from io import StringIO

from app.models.transcript import TranscriptCourse


def parse_transcript_csv(content: str) -> list[TranscriptCourse]:
    reader = csv.DictReader(StringIO(content))
    rows = []
    for row in reader:
        course_code = row.get("course_code") or row.get("code") or row.get("course")
        if not course_code:
            continue
        rows.append(
            TranscriptCourse(
                course_code=course_code.strip(),
                course_title=row.get("course_title") or row.get("title"),
                credits=_to_int(row.get("credits")),
                term=row.get("term"),
                grade=row.get("grade"),
                confidence=None,
            )
        )
    return rows


def parse_catalog_csv(content: str) -> list[dict]:
    reader = csv.DictReader(StringIO(content))
    rows = []
    for row in reader:
        code = row.get("course_code") or row.get("code") or row.get("course")
        if not code:
            continue
        rows.append(
            {
                "code": code.strip(),
                "title": row.get("course_title") or row.get("title"),
                "credits": _to_int(row.get("credits")),
                "availability": row.get("availability"),
                "honors_only": str(row.get("honors_only", "")).lower()
                in {"true", "1", "yes"},
            }
        )
    return rows


def parse_transcript_text(content: str) -> list[TranscriptCourse]:
    """Detect transcript format and parse accordingly.

    Supports:
    - Philander Smith University columnar format (primary)
    - Generic free-text fallback
    """
    if _PSU_TERM_RE.search(content):
        return _parse_psu_transcript(content)
    return _parse_generic_transcript(content)


# ── Philander Smith University format ────────────────────────────────────────

# "2022-2023 Academic Year : Fall Semester"
_PSU_TERM_RE = re.compile(
    r"(\d{4})-(\d{4})\s+Academic\s+Year\s*:\s*(Fall|Spring|Summer)\s+Semester",
    re.IGNORECASE,
)

# "CSCI-123 Programming I LT A 3.00 3.00 3.00 12.00"
# "MTH -215 Calculus I - HYBRID LT A 5.00 5.00 5.00 20.00"
# "CSCI-143 Applied Comp Science LTA 3.00 3.00 3.00 12.00"   (LTA = LT + A no space)
# "CSCI-373 Machine Learning LT WIP 3.00 0.00 0.00 0.00"
_PSU_COURSE_RE = re.compile(
    r"^([A-Z]{2,5})\s*-\s*(\d{3})\s+(.+?)\s+LT\s*([A-Z+\-]+)\s+([\d]+\.[\d]+)",
    re.IGNORECASE,
)

# Lines we always skip
_PSU_SKIP_RE = re.compile(
    r"^(Term Totals|Career Totals|Page\s*:|Copy of Transcript|Undergraduate Division|"
    r"Course Number|Bertha|Philander Smith|900 Daisy|ID\s*:|Name\s*:|Address|"
    r"Abuja|Degree Information|Major|Minor|Registrar|Transcript Official|"
    r"\*\s*Means|R\s*Means|ACCREDITATION|HISTORY|FAMILY EDUCATIONAL|"
    r"UNIT OF CREDIT|COURSE NUM|GRADES|REPEATED|FRAUDULENT|OFFICIAL)",
    re.IGNORECASE,
)


def _psu_term_label(year1: str, year2: str, semester: str) -> str:
    sem = semester.upper()
    if sem == "FALL":
        return f"Fall {year1}"
    if sem == "SPRING":
        return f"Spring {year2}"
    return f"Summer {year2}"  # Summer belongs to second year


def _parse_psu_transcript(content: str) -> list[TranscriptCourse]:
    rows: list[TranscriptCourse] = []
    current_term: str | None = None

    for raw_line in content.splitlines():
        line = raw_line.strip()
        # Strip trailing "Copy of Transcript" artifact
        line = re.sub(r"\.?\s*Copy of Transcript.*$", "", line, flags=re.IGNORECASE).strip()
        if not line:
            continue
        if _PSU_SKIP_RE.match(line):
            continue

        # Term header?
        tm = _PSU_TERM_RE.search(line)
        if tm:
            current_term = _psu_term_label(tm.group(1), tm.group(2), tm.group(3))
            continue

        # Course row?
        cm = _PSU_COURSE_RE.match(line)
        if not cm:
            continue

        dept       = cm.group(1).upper()
        num        = cm.group(2)
        raw_title  = cm.group(3).strip()
        grade_raw  = cm.group(4).upper()
        credits_str= cm.group(5)

        code = f"{dept} {num}"

        # Clean up title
        title = re.sub(r"\s*-\s*HYBRID\b", " (Hybrid)", raw_title, flags=re.IGNORECASE)
        title = re.sub(r"\s*-\s*ONLINE\b", " (Online)", title, flags=re.IGNORECASE)
        title = title.strip(" -")

        # Grade / WIP
        in_progress = grade_raw == "WIP"
        grade = None if in_progress or grade_raw in ("TR",) else grade_raw

        # Credits — the first number is always the planned credit hours
        try:
            credits = int(float(credits_str))
        except (ValueError, TypeError):
            credits = None

        confidence = 1.0 if not in_progress else 0.85
        if not current_term:
            confidence -= 0.20

        rows.append(
            TranscriptCourse(
                course_code=code,
                course_title=title,
                credits=credits,
                term=current_term,
                grade="WIP" if in_progress else grade,
                confidence=round(confidence, 2),
            )
        )
    return rows


# ── Generic fallback ──────────────────────────────────────────────────────────

def _parse_generic_transcript(content: str) -> list[TranscriptCourse]:
    rows: list[TranscriptCourse] = []
    term = None
    for line in _normalize_lines(content):
        term_match = _TERM_RE.search(line)
        if term_match:
            term = f"{term_match.group(1).title()} {term_match.group(2)}"
            continue

        code_match = _COURSE_RE.search(line)
        if not code_match:
            continue

        code = f"{code_match.group(1)} {code_match.group(2)}"
        title = _extract_title(line, code_match.end())
        credits = _extract_credits(line)
        grade = _extract_grade(line)
        confidence = _compute_confidence(term, credits, grade)

        rows.append(
            TranscriptCourse(
                course_code=code,
                course_title=title,
                credits=credits,
                term=term,
                grade=grade,
                confidence=confidence,
            )
        )
    return rows


def parse_catalog_text(content: str) -> list[dict]:
    rows: list[dict] = []
    for line in _normalize_lines(content):
        code_match = _COURSE_RE.search(line)
        if not code_match:
            continue
        code = f"{code_match.group(1)} {code_match.group(2)}"
        title = _extract_title(line, code_match.end())
        credits = _extract_credits(line)
        if not title and not credits:
            continue
        rows.append(
            {
                "code": code,
                "title": title,
                "credits": credits,
                "availability": _extract_availability(line),
                "honors_only": "honors" in line.lower(),
            }
        )
    return rows


def parse_prereq_text(content: str) -> list[dict]:
    rows: list[dict] = []
    for line in _normalize_lines(content):
        codes = [
            f"{m.group(1)} {m.group(2)}" for m in _COURSE_RE.finditer(line)
        ]
        if len(codes) < 2:
            continue
        relation = "required"
        lower = line.lower()
        if "coreq" in lower or "co-req" in lower or "co req" in lower:
            relation = "coreq"
        elif "optional" in lower or "or" in lower:
            relation = "optional"
        course_code = codes[0]
        for prereq_code in codes[1:]:
            rows.append(
                {
                    "course_code": course_code,
                    "prereq_code": prereq_code,
                    "relation": relation,
                }
            )
    return rows


def _compute_confidence(term: str | None, credits: int | None, grade: str | None) -> float:
    """Score 0.4–1.0: base for code match + bonuses for each additional field found."""
    score = 0.40
    if term:
        score += 0.30
    if credits is not None:
        score += 0.20
    if grade:
        score += 0.10
    return round(score, 2)


def _to_int(value: str | None):
    if value is None:
        return None
    try:
        return int(float(value))
    except ValueError:
        return None


_TERM_RE = re.compile(r"\b(Spring|Summer|Fall|Winter)\s+(20\d{2})\b", re.I)
_COURSE_RE = re.compile(r"\b([A-Z]{2,4})\s?-?\s?(\d{3}[A-Z]?)\b")
_CREDITS_RE = re.compile(r"(\d+(?:\.\d+)?)\s*(?:cr|credits)\b", re.I)
_GRADE_RE = re.compile(r"\b([ABCDF][+-]?)\b")


def _normalize_lines(content: str):
    for line in content.splitlines():
        clean = re.sub(r"\s+", " ", line).strip()
        if clean:
            yield clean


def _extract_title(line: str, start_index: int) -> str | None:
    tail = line[start_index:].strip(" -–—\t")
    if not tail:
        return None
    tail = _CREDITS_RE.sub("", tail)
    tail = re.sub(r"\b\d+(?:\.\d+)?\b", "", tail)
    tail = tail.replace("\u2022", "").strip(" -–—\t")
    return tail if tail else None


def _extract_credits(line: str) -> int | None:
    match = _CREDITS_RE.search(line)
    if match:
        return _to_int(match.group(1))
    return None


def _extract_grade(line: str) -> str | None:
    match = _GRADE_RE.search(line)
    if match:
        return match.group(1)
    return None


def _extract_availability(line: str) -> str | None:
    lower = line.lower()
    seasons = []
    for season in ("fall", "spring", "summer", "winter"):
        if season in lower:
            seasons.append(season.title())
    return ",".join(seasons) if seasons else None
