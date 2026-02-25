from dataclasses import dataclass


@dataclass
class CoReqGroup:
    course: str
    coreq: str


def build_coreq_map(coreqs: list[CoReqGroup]) -> dict[str, set[str]]:
    mapping: dict[str, set[str]] = {}
    for row in coreqs:
        mapping.setdefault(row.course, set()).add(row.coreq)
    return mapping
