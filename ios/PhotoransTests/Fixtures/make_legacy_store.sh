#!/usr/bin/env bash
#
# 旧 HistoryEntry schema 風の SQLite (`legacy_history_v1.sqlite`) を生成し、
# 同ディレクトリに置く。`StoreBootstrapTests.swift` のフィクスチャとして利用する。
#
# 旧 schema (本リポジトリの履歴: `ios/Photorans/Storage/HistoryEntry.swift` を Phase 1 で削除)
# は SwiftData により SQLite store として永続化されており、CoreData 由来の
# 命名規則で `Z_METADATA` / `Z_PRIMARYKEY` / `ZHISTORYENTRY` テーブルを持つ。
# 新 schema (`Item` / `ItemGroup`) でこのファイルを `ModelContainer` に渡すと、
# entity 不一致 + 互換性 metadata の不在で migration が失敗し、
# `StoreBootstrap.makeContainer` のフォールバックが発火する。
#
# Plan (docs/plans/home-screen-h4-impl.md) Step 1.7 に従い、生成した
# `legacy_history_v1.sqlite` 自体もコミットする (再生成手順だけだと CI で
# 環境差で揺れる可能性があるため)。Linux / macOS どちらでも `python3` の
# 標準 `sqlite3` モジュール経由で生成する。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT="$SCRIPT_DIR/legacy_history_v1.sqlite"

rm -f "$OUTPUT" "$OUTPUT-shm" "$OUTPUT-wal"

python3 - "$OUTPUT" <<'PY'
import sqlite3
import sys

path = sys.argv[1]
con = sqlite3.connect(path)
cur = con.cursor()
cur.executescript("""
CREATE TABLE Z_METADATA (
    Z_VERSION INTEGER PRIMARY KEY,
    Z_UUID VARCHAR(255),
    Z_PLIST BLOB
);
CREATE TABLE Z_PRIMARYKEY (
    Z_ENT INTEGER PRIMARY KEY,
    Z_NAME VARCHAR,
    Z_SUPER INTEGER,
    Z_MAX INTEGER
);
CREATE TABLE ZHISTORYENTRY (
    Z_PK INTEGER PRIMARY KEY,
    Z_ENT INTEGER,
    Z_OPT INTEGER,
    ZID BLOB,
    ZCREATEDAT TIMESTAMP,
    ZIMAGEPATH VARCHAR,
    ZORIGINALTEXT VARCHAR,
    ZTRANSLATEDTEXT VARCHAR,
    ZMODEL VARCHAR
);
INSERT INTO Z_METADATA (Z_VERSION, Z_UUID, Z_PLIST)
VALUES (1, 'photorans-legacy-history-v1', NULL);
INSERT INTO Z_PRIMARYKEY (Z_ENT, Z_NAME, Z_SUPER, Z_MAX)
VALUES (1, 'HistoryEntry', 0, 1);
INSERT INTO ZHISTORYENTRY (
    Z_PK, Z_ENT, Z_OPT,
    ZID, ZCREATEDAT, ZIMAGEPATH, ZORIGINALTEXT, ZTRANSLATEDTEXT, ZMODEL
)
VALUES (
    1, 1, 1,
    randomblob(16), 0, 'photos/legacy.jpg',
    'old original', 'old translated', 'legacy-model'
);
""")
con.commit()
con.close()
PY

echo "Generated: $OUTPUT"
