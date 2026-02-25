from collections import defaultdict, deque
from dataclasses import dataclass


@dataclass
class PrereqGraph:
    nodes: set[str]
    edges: dict[str, set[str]]  # prereq -> dependents
    prereqs: dict[str, set[str]]  # course -> prereqs


def build_graph(prereq_map: dict[str, set[str]]) -> PrereqGraph:
    nodes = set(prereq_map.keys())
    edges: dict[str, set[str]] = defaultdict(set)
    prereqs: dict[str, set[str]] = defaultdict(set)

    for course, reqs in prereq_map.items():
        nodes.update(reqs)
        prereqs[course].update(reqs)
        for req in reqs:
            edges[req].add(course)

    return PrereqGraph(nodes=nodes, edges=edges, prereqs=prereqs)


def topo_sort(graph: PrereqGraph) -> list[str]:
    indegree = {n: 0 for n in graph.nodes}
    for course, reqs in graph.prereqs.items():
        indegree.setdefault(course, 0)
        for req in reqs:
            indegree[course] += 1

    queue = deque([n for n, d in indegree.items() if d == 0])
    order: list[str] = []

    while queue:
        node = queue.popleft()
        order.append(node)
        for nxt in graph.edges.get(node, set()):
            indegree[nxt] -= 1
            if indegree[nxt] == 0:
                queue.append(nxt)

    if len(order) != len(indegree):
        raise ValueError("Cycle detected in prerequisites")

    return order
