"""
Coverage for negative and large-magnitude rowids in vec0 tables.

vec0 accepts any i64 rowid, and downstream applications assign
deterministic negative rowids (e.g. rowid = -source_id). These tests
exercise insert, point lookup, update, delete, KNN result reporting,
metadata/auxiliary/partition columns, and the KNN `rowid IN (...)`
filter with rowids that are negative and/or span more than 2^31.
"""

import sqlite3

import pytest

INT64_MIN = -(2**63)
INT64_MAX = 2**63 - 1


def test_insert_and_point_lookup(db):
    db.execute("CREATE VIRTUAL TABLE v USING vec0(embedding float[2])")
    rowids = [INT64_MIN, -4_000_000_000, -42, -1, 0, 1, 4_000_000_000, INT64_MAX]
    for i, rowid in enumerate(rowids):
        db.execute(
            "INSERT INTO v(rowid, embedding) VALUES (?, ?)", [rowid, f"[{i}, {i}]"]
        )

    for i, rowid in enumerate(rowids):
        row = db.execute(
            "SELECT rowid, vec_to_json(embedding) AS e FROM v WHERE rowid = ?",
            [rowid],
        ).fetchone()
        assert row["rowid"] == rowid
        assert row["e"] == f"[{i}.000000,{i}.000000]"

    assert db.execute("SELECT count(*) FROM v").fetchone()[0] == len(rowids)


def test_update(db):
    db.execute("CREATE VIRTUAL TABLE v USING vec0(embedding float[2])")
    db.execute("INSERT INTO v(rowid, embedding) VALUES (-7, '[1, 1]')")
    db.execute("UPDATE v SET embedding = '[9, 9]' WHERE rowid = -7")
    row = db.execute(
        "SELECT vec_to_json(embedding) AS e FROM v WHERE rowid = -7"
    ).fetchone()
    assert row["e"] == "[9.000000,9.000000]"


def test_delete(db):
    db.execute("CREATE VIRTUAL TABLE v USING vec0(embedding float[2])")
    for rowid in [-3, -2, -1, 1, 2]:
        db.execute(
            "INSERT INTO v(rowid, embedding) VALUES (?, ?)",
            [rowid, f"[{rowid}, {rowid}]"],
        )
    db.execute("DELETE FROM v WHERE rowid = -2")
    remaining = [r[0] for r in db.execute("SELECT rowid FROM v ORDER BY rowid")]
    assert remaining == [-3, -1, 1, 2]
    assert db.execute("SELECT count(*) FROM v WHERE rowid = -2").fetchone()[0] == 0
    # a deleted negative rowid can be re-inserted
    db.execute("INSERT INTO v(rowid, embedding) VALUES (-2, '[5, 5]')")
    assert db.execute("SELECT count(*) FROM v WHERE rowid = -2").fetchone()[0] == 1


def test_duplicate_negative_rowid_rejected(db):
    db.execute("CREATE VIRTUAL TABLE v USING vec0(embedding float[2])")
    db.execute("INSERT INTO v(rowid, embedding) VALUES (-7, '[1, 1]')")
    with pytest.raises(sqlite3.OperationalError, match="UNIQUE constraint failed"):
        db.execute("INSERT INTO v(rowid, embedding) VALUES (-7, '[2, 2]')")


def test_knn_reports_negative_rowids(db):
    db.execute("CREATE VIRTUAL TABLE v USING vec0(embedding float[2])")
    # rowid -i holds [i, i], so KNN order from origin is -1, -2, -3, ...
    for i in range(1, 11):
        db.execute("INSERT INTO v(rowid, embedding) VALUES (?, ?)", [-i, f"[{i}, {i}]"])
    rows = db.execute(
        "SELECT rowid, distance FROM v WHERE embedding MATCH '[0, 0]' AND k = 3 "
        "ORDER BY distance"
    ).fetchall()
    assert [r["rowid"] for r in rows] == [-1, -2, -3]


def test_knn_negative_rowids_across_chunks(db):
    db.execute("CREATE VIRTUAL TABLE v USING vec0(embedding float[1], chunk_size=8)")
    for i in range(-25, 25):
        db.execute("INSERT INTO v(rowid, embedding) VALUES (?, ?)", [i, f"[{i}]"])
    db.execute("DELETE FROM v WHERE rowid IN (-25, -1, 0, 24)")
    rows = db.execute(
        "SELECT rowid FROM v WHERE embedding MATCH '[0]' AND k = 4 ORDER BY distance"
    ).fetchall()
    assert sorted(r["rowid"] for r in rows) == [-3, -2, 1, 2]


def test_metadata_filter_with_negative_rowids(db):
    db.execute("CREATE VIRTUAL TABLE v USING vec0(embedding float[2], category TEXT)")
    for i in range(1, 11):
        category = "even" if i % 2 == 0 else "odd"
        db.execute(
            "INSERT INTO v(rowid, embedding, category) VALUES (?, ?, ?)",
            [-i, f"[{i}, {i}]", category],
        )
    rows = db.execute(
        "SELECT rowid, category FROM v "
        "WHERE embedding MATCH '[0, 0]' AND k = 3 AND category = 'even' "
        "ORDER BY distance"
    ).fetchall()
    assert [r["rowid"] for r in rows] == [-2, -4, -6]
    assert all(r["category"] == "even" for r in rows)


def test_auxiliary_and_partition_with_negative_rowids(db):
    db.execute(
        "CREATE VIRTUAL TABLE v USING vec0("
        "  user_id INTEGER partition key, embedding float[2], +contents TEXT"
        ")"
    )
    for i in range(1, 7):
        db.execute(
            "INSERT INTO v(rowid, user_id, embedding, contents) VALUES (?, ?, ?, ?)",
            [-i, i % 2, f"[{i}, {i}]", f"item {i}"],
        )
    rows = db.execute(
        "SELECT rowid, contents FROM v "
        "WHERE embedding MATCH '[0, 0]' AND k = 2 AND user_id = 0 "
        "ORDER BY distance"
    ).fetchall()
    assert [r["rowid"] for r in rows] == [-2, -4]
    assert [r["contents"] for r in rows] == ["item 2", "item 4"]


def test_knn_rowid_in_negative(db):
    db.execute("CREATE VIRTUAL TABLE v USING vec0(embedding float[2])")
    for i in range(1, 11):
        db.execute("INSERT INTO v(rowid, embedding) VALUES (?, ?)", [-i, f"[{i}, {i}]"])
    rows = db.execute(
        "SELECT rowid FROM v WHERE embedding MATCH '[0, 0]' AND k = 10 "
        "AND rowid IN (-2, -5, -9) ORDER BY distance"
    ).fetchall()
    assert [r["rowid"] for r in rows] == [-2, -5, -9]


def test_knn_rowid_in_span_exceeding_2_31(db):
    """Regression test: the qsort/bsearch comparator for `rowid IN (...)`
    returned the i64 rowid difference narrowed to int. The subtraction can
    overflow and the narrowing keeps only the low 32 bits, so unequal
    rowids could compare as equal or with the wrong sign (a difference of
    2^31 wraps negative), giving qsort an inconsistent ordering and making
    bsearch silently drop matching rowids from KNN results."""
    db.execute("CREATE VIRTUAL TABLE v USING vec0(embedding float[1])")
    rowids = [
        -4_000_000_000,
        -(2**31) - 7,
        0,
        2**31,
        2**32 + 5,
        4_000_000_000,
    ]
    for i, rowid in enumerate(rowids):
        db.execute("INSERT INTO v(rowid, embedding) VALUES (?, ?)", [rowid, f"[{i}]"])
    placeholders = ",".join("?" * len(rowids))
    rows = db.execute(
        f"SELECT rowid FROM v WHERE embedding MATCH '[0]' AND k = {len(rowids)} "
        f"AND rowid IN ({placeholders}) ORDER BY distance",
        rowids,
    ).fetchall()
    assert sorted(r["rowid"] for r in rows) == sorted(rowids)
