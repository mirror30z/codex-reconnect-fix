"""Read only recent network signatures; never print raw log bodies or thread IDs."""
import collections
import contextlib
import datetime
import json
import pathlib
import re
import sqlite3
import sys


def classify(body):
    markers = []
    for code in ("10053", "10054", "10060", "10061"):
        if re.search(r"os error\s+" + code + r"\b", body, re.I):
            markers.append("socket-" + code)
    for key, pattern in {
        "http-401": r"(?:status|HTTP)\s*401\b",
        "http-403": r"(?:status|HTTP)\s*403\b",
        "http-429": r"(?:status|HTTP)\s*429\b",
        "http-5xx": r"(?:status|HTTP)\s*5\d\d\b",
        "timeout": r"timed out|timeout",
        "closed-before-completion": r"closed by server before response.completed",
        "http-fallback": r"falling back.*(?:HTTP|HTTPS)|responses_http",
        "response-decode": r"error decoding response body",
    }.items():
        if re.search(pattern, body, re.I):
            markers.append(key)
    return markers


def main():
    db = pathlib.Path(sys.argv[1]) / "logs_2.sqlite"
    if not db.is_file():
        print(json.dumps({"available": False, "reason": "log-database-missing"}))
        return
    with contextlib.closing(sqlite3.connect(db.resolve().as_uri() + "?mode=ro", uri=True, timeout=1)) as connection:
        anchor = connection.execute("SELECT max(ts) FROM logs").fetchone()[0] or 0
        rows = connection.execute(
            "SELECT ts,target,feedback_log_body FROM logs WHERE ts>? "
            "AND level IN ('WARN','ERROR') AND (target LIKE '%responses_retry%' "
            "OR target LIKE '%responses_websocket%' OR target LIKE '%startup_prewarm%' "
            "OR target LIKE '%remote_control::websocket%') ORDER BY ts DESC LIMIT 2000",
            (anchor - 86400,),
        ).fetchall()
    counts = collections.Counter()
    recent = []
    for ts, target, body in rows:
        body = body or ""
        transport = "remote-control" if "remote_control" in target else "model"
        markers = classify(body)
        retry = re.search(r"retrying sampling request \((\d+)/(\d+)", body)
        if retry and retry[1] == retry[2]:
            markers.append("retry-limit-reached")
        for marker in markers:
            counts[transport + ":" + marker] += 1
        if markers and len(recent) < 12:
            recent.append({"utc": datetime.datetime.fromtimestamp(ts, datetime.timezone.utc).isoformat(),
                           "transport": transport, "markers": markers})
    print(json.dumps({"available": True, "windowHours": 24, "windowBasis": "latest-log-timestamp",
                      "anchorUtc": datetime.datetime.fromtimestamp(anchor, datetime.timezone.utc).isoformat(),
                      "sampledRecords": len(rows),
                      "capReached": len(rows) == 2000, "counts": counts, "recent": recent}))


if __name__ == "__main__":
    try:
        main()
    except (OSError, sqlite3.Error):
        print(json.dumps({"available": False, "reason": "log-read-failed-not-proof-of-corruption"}))
