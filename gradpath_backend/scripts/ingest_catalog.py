"""Ingest a course catalog into the GradPath database.

Expected CSV columns (header required):
  code         - course code, e.g. "CSCI 101"
  title        - full course name, e.g. "Intro to Computer Science"
  credits      - integer credit hours, e.g. "3"
  prereqs      - comma-separated prereq codes, e.g. "CSCI 100,MATH 101"  (leave blank if none)
  term_offered - comma-separated seasons, e.g. "Fall,Spring"  (leave blank for all terms)

Expected JSON format: a list of objects with the same field names.
  [{"code": "CSCI 101", "title": "...", "credits": 3, "prereqs": "CSCI 100", "term_offered": "Fall,Spring"}, ...]

Usage:
  cd gradpath_backend
  python -m scripts.ingest_catalog --file path/to/catalog.csv
  python -m scripts.ingest_catalog --file path/to/catalog.json
"""
import argparse
import csv
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from app.core.database import SessionLocal  # noqa: E402
from app.models.course import Course  # noqa: E402
from app.models.prerequisite import Prerequisite  # noqa: E402


def _to_int(v) -> int | None:
    if v is None:
        return None
    try:
        return int(float(str(v)))
    except (ValueError, TypeError):
        return None


def ingest_rows(rows: list[dict]) -> None:
    db = SessionLocal()
    new_courses = 0
    new_prereqs = 0
    try:
        for row in rows:
            code = (row.get("code") or "").strip()
            if not code:
                continue

            existing = db.query(Course).filter(Course.code == code).first()
            if existing:
                existing.title = existing.title or row.get("title")
                existing.credits = existing.credits or _to_int(row.get("credits"))
                existing.availability = existing.availability or row.get("term_offered")
                db.add(existing)
            else:
                db.add(
                    Course(
                        code=code,
                        title=row.get("title"),
                        credits=_to_int(row.get("credits")),
                        availability=row.get("term_offered"),
                        honors_only=False,
                    )
                )
                new_courses += 1

            prereqs_raw = row.get("prereqs") or ""
            for prereq_code in [p.strip() for p in prereqs_raw.split(",") if p.strip()]:
                exists = (
                    db.query(Prerequisite)
                    .filter(
                        Prerequisite.course_code == code,
                        Prerequisite.prereq_code == prereq_code,
                        Prerequisite.relation == "required",
                    )
                    .first()
                )
                if not exists:
                    db.add(
                        Prerequisite(
                            course_code=code,
                            prereq_code=prereq_code,
                            relation="required",
                        )
                    )
                    new_prereqs += 1

        db.commit()
        print(f"Done: {new_courses} new courses, {new_prereqs} new prerequisites.")
    except Exception as exc:
        db.rollback()
        print(f"Error during ingestion: {exc}")
        raise
    finally:
        db.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="Ingest course catalog into GradPath DB")
    parser.add_argument("--file", required=True, help="Path to .csv or .json catalog file")
    args = parser.parse_args()

    path: str = args.file
    if not os.path.exists(path):
        print(f"File not found: {path}")
        sys.exit(1)

    if path.endswith(".json"):
        with open(path, encoding="utf-8") as f:
            rows = json.load(f)
    elif path.endswith(".csv"):
        with open(path, encoding="utf-8") as f:
            rows = list(csv.DictReader(f))
    else:
        print("Unsupported format. Use .csv or .json")
        sys.exit(1)

    ingest_rows(rows)


if __name__ == "__main__":
    main()
