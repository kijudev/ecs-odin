"""Merges the benchmark CSVs into side-by-side tables. Usage: python3 compare.py build/*.csv"""

import csv
import sys
from collections import defaultdict

LIBS = ["oecs", "entt", "flecs", "flecs-parent"]

MEMORY = [
    ("empty world", "lifecycle.spawn.0", "live", False),
    ("spawn 4 parts (peak)", "lifecycle.spawn.4", "peak", True),
    ("full (A-D)", "query.uniform.4", "live", True),
    ("sparse 10%", "query.sparse.100", "live", True),
    ("fragmented", "query.fragmented.1", "live", True),
    ("after churn", "churn.after", "live", True),
    ("tree", "hierarchy.propagate.tree", "live", True),
    ("forest", "hierarchy.propagate.forest", "live", True),
]


def load(paths):
    rows = defaultdict(dict)  # (n, id) -> lib -> row
    for path in paths:
        with open(path) as f:
            for row in csv.DictReader(f):
                rows[(int(row["n"]), row["group"] + "." + row["case"])][row["lib"]] = (
                    row
                )
    return rows


def fmt_ns(ns):
    if ns < 10:
        return f"{ns:.2f}"
    if ns < 100:
        return f"{ns:.1f}"
    return f"{ns:,.0f}"


def fmt_bytes(b):
    for unit in ["B", "KB", "MB", "GB"]:
        if b < 1024 or unit == "GB":
            return f"{b:.0f} {unit}" if unit == "B" else f"{b:.1f} {unit}"
        b /= 1024


def table(header, lines):
    widths = [
        max(len(str(line[i])) for line in [header] + lines) for i in range(len(header))
    ]
    out = [
        "  ".join(
            h.ljust(w) if i == 0 else h.rjust(w)
            for i, (h, w) in enumerate(zip(header, widths))
        )
    ]
    out.append("  ".join("-" * w for w in widths))
    for line in lines:
        out.append(
            "  ".join(
                str(c).ljust(w) if i == 0 else str(c).rjust(w)
                for i, (c, w) in enumerate(zip(line, widths))
            )
        )
    return "\n".join(out)


def main():
    rows = load(sys.argv[1:])
    libs = [lib for lib in LIBS if any(lib in r for r in rows.values())]
    sizes = sorted({n for n, _ in rows})
    ids = list(dict.fromkeys(i for _, i in rows))  # keeps the binaries' case order

    print("ns/op, median.  * fastest   ~ noisy (MAD > 10%)   ! checksums disagree")
    print(
        "oecs/best: oecs time over the best other library, below 1 means oecs is faster\n"
    )

    for n in sizes:
        groups = defaultdict(list)
        for i in ids:
            if (n, i) in rows:
                groups[i.split(".")[0]].append(i)

        for group, group_ids in groups.items():
            lines = []
            for i in group_ids:
                by_lib = rows[(n, i)]
                times = {lib: float(r["median_ns_op"]) for lib, r in by_lib.items()}
                best = min(times.values())
                checksums = {float(r["checksum"]) for r in by_lib.values()}

                line = [i.split(".", 1)[1] + (" !" if len(checksums) > 1 else "")]
                for lib in libs:
                    r = by_lib.get(lib)
                    if not r:
                        line.append("-")
                        continue
                    t = times[lib]
                    noisy = float(r["mad_ns_op"]) > 0.1 * t
                    line.append(
                        fmt_ns(t)
                        + ("*" if t == best and len(times) > 1 else " ")
                        + ("~" if noisy else " ")
                    )

                others = [t for lib, t in times.items() if lib != "oecs"]
                line.append(
                    f"{times['oecs'] / min(others):.2f}"
                    if "oecs" in times and others
                    else "-"
                )
                lines.append(line)

            print(f"## {group}, n = {n:,}\n")
            print(table(["case"] + libs + ["oecs/best"], lines))
            print()

        lines = []
        for label, i, field, per_entity in MEMORY:
            if (n, i) not in rows:
                continue
            line = [label + (" (B/entity)" if per_entity else "")]
            for lib in libs:
                r = rows[(n, i)].get(lib)
                if not r:
                    line.append("-")
                    continue
                b = float(r[field + "_bytes"])
                line.append(f"{b / n:.1f}" if per_entity else fmt_bytes(b))
            lines.append(line)

        if lines:
            print(f"## memory, n = {n:,}\n")
            print(table(["setup"] + libs, lines))
            print()


if __name__ == "__main__":
    main()
