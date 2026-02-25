from dataclasses import dataclass


@dataclass
class CourseOffering:
    code: str
    credits: int
    availability: set[str]
    honors_only: bool


@dataclass
class ScheduleResult:
    terms: list[dict]
    bottlenecks: list[str]


def schedule_terms(
    ordered_courses: list[str],
    offerings: dict[str, CourseOffering],
    prereqs: dict[str, set[str]],
    coreqs: dict[str, set[str]],
    optional_prereqs: dict[str, set[str]],
    completed: set[str],
    max_credits: int,
    allow_summer: bool,
    honors_only: bool,
    start_year: int | None = None,
    start_term: str | None = None,
) -> ScheduleResult:
    terms = []
    bottlenecks = []
    queue = [c for c in ordered_courses if c not in completed]

    term_names = ["Spring", "Fall"]
    if allow_summer:
        term_names = ["Spring", "Summer", "Fall"]

    if start_term:
        start_term = start_term.title()
        if start_term in term_names:
            while term_names[0] != start_term:
                term_names.append(term_names.pop(0))

    year = start_year or 1
    max_year = year + 12  # allow up to 12 years to handle large catalogs
    while queue:
        for term in term_names:
            current = []
            credits = 0
            remaining = []
            for course in queue:
                offering = offerings.get(course)
                if offering is None:
                    remaining.append(course)
                    continue
                if offering.honors_only and not honors_only:
                    bottlenecks.append(f"Honors-only course blocked: {course}")
                    continue
                if term not in offering.availability:
                    remaining.append(course)
                    continue
                course_prereqs = prereqs.get(course, set())
                if not course_prereqs.issubset(completed):
                    remaining.append(course)
                    continue
                optional = optional_prereqs.get(course, set())
                if optional and not optional.intersection(completed):
                    bottlenecks.append(
                        f"Optional prereq missing for {course}: {', '.join(sorted(optional))}"
                    )
                course_coreqs = coreqs.get(course, set())
                if course_coreqs and not course_coreqs.intersection(current):
                    remaining.append(course)
                    continue
                if credits + offering.credits > max_credits:
                    remaining.append(course)
                    continue
                current.append(course)
                credits += offering.credits
                completed.add(course)

            queue = remaining
            if current:
                terms.append(
                    {
                        "term": f"{term} {year}",
                        "courses": current,
                        "credits": credits,
                    }
                )
            if term == "Fall":
                year += 1
        if year > max_year:
            bottlenecks.append("Scheduling exceeded 6 years")
            break

    return ScheduleResult(terms=terms, bottlenecks=bottlenecks)
