import Database from 'better-sqlite3';
import { mkdirSync, unlinkSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { randomUUID } from 'node:crypto';

const MAX_HISTORY_RECORDS = 10_000;

export const dataDir = resolve(process.env.DATA_DIR ?? './data');
const imagesDir = join(dataDir, 'images');
const dbPath = join(dataDir, 'history.db');

mkdirSync(imagesDir, { recursive: true });

const db = new Database(dbPath);
db.pragma('journal_mode = WAL');
db.exec(`
  CREATE TABLE IF NOT EXISTS history (
    id TEXT PRIMARY KEY,
    createdAt TEXT NOT NULL,
    imagePath TEXT NOT NULL,
    imageMimeType TEXT NOT NULL,
    originalText TEXT NOT NULL,
    translatedText TEXT NOT NULL,
    model TEXT NOT NULL,
    inputTokens INTEGER,
    outputTokens INTEGER,
    cacheCreationInputTokens INTEGER,
    cacheReadInputTokens INTEGER,
    sourceLanguage TEXT,
    targetLanguage TEXT
  );
  CREATE INDEX IF NOT EXISTS idx_history_createdAt ON history(createdAt DESC);
`);

const existingColumns = new Set(
  (db.pragma('table_info(history)') as Array<{ name: string }>).map((c) => c.name),
);
for (const col of ['inputTokens', 'outputTokens', 'cacheCreationInputTokens', 'cacheReadInputTokens']) {
  if (!existingColumns.has(col)) {
    db.exec(`ALTER TABLE history ADD COLUMN ${col} INTEGER`);
  }
}
for (const col of ['sourceLanguage', 'targetLanguage']) {
  if (!existingColumns.has(col)) {
    db.exec(`ALTER TABLE history ADD COLUMN ${col} TEXT`);
  }
}

const insertStmt = db.prepare(`
  INSERT INTO history (
    id, createdAt, imagePath, imageMimeType, originalText, translatedText, model,
    inputTokens, outputTokens, cacheCreationInputTokens, cacheReadInputTokens,
    sourceLanguage, targetLanguage
  )
  VALUES (
    @id, @createdAt, @imagePath, @imageMimeType, @originalText, @translatedText, @model,
    @inputTokens, @outputTokens, @cacheCreationInputTokens, @cacheReadInputTokens,
    @sourceLanguage, @targetLanguage
  )
`);

const countStmt = db.prepare(`SELECT COUNT(*) AS c FROM history`);
const oldestStmt = db.prepare(`
  SELECT id, imagePath FROM history ORDER BY createdAt ASC, id ASC LIMIT ?
`);
const deleteByIdStmt = db.prepare(`DELETE FROM history WHERE id = ?`);

function pruneOldHistory(): void {
  const total = (countStmt.get() as { c: number }).c;
  if (total <= MAX_HISTORY_RECORDS) return;

  const excess = total - MAX_HISTORY_RECORDS;
  const victims = oldestStmt.all(excess) as Array<{ id: string; imagePath: string }>;

  for (const v of victims) {
    deleteByIdStmt.run(v.id);
    try {
      unlinkSync(join(dataDir, v.imagePath));
    } catch (err) {
      const code = (err as NodeJS.ErrnoException).code;
      if (code !== 'ENOENT') {
        console.warn(`failed to unlink old image ${v.imagePath}:`, err);
      }
    }
  }
}

const MIME_TO_EXT: Record<string, string> = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/gif': 'gif',
  'image/webp': 'webp',
};

export interface SaveHistoryInput {
  imageBytes: Buffer;
  imageMimeType: string;
  originalText: string;
  translatedText: string;
  sourceLanguage: string;
  targetLanguage: string;
  model: string;
  inputTokens?: number | null;
  outputTokens?: number | null;
  cacheCreationInputTokens?: number | null;
  cacheReadInputTokens?: number | null;
}

export interface SaveHistoryResult {
  id: string;
  createdAt: string;
  imagePath: string;
}

export function saveHistory(input: SaveHistoryInput): SaveHistoryResult {
  const id = randomUUID();
  const ext = MIME_TO_EXT[input.imageMimeType] ?? 'bin';
  const imagePath = join('images', `${id}.${ext}`);
  const createdAt = new Date().toISOString();

  writeFileSync(join(dataDir, imagePath), input.imageBytes);

  insertStmt.run({
    id,
    createdAt,
    imagePath,
    imageMimeType: input.imageMimeType,
    originalText: input.originalText,
    translatedText: input.translatedText,
    model: input.model,
    inputTokens: input.inputTokens ?? null,
    outputTokens: input.outputTokens ?? null,
    cacheCreationInputTokens: input.cacheCreationInputTokens ?? null,
    cacheReadInputTokens: input.cacheReadInputTokens ?? null,
    sourceLanguage: input.sourceLanguage,
    targetLanguage: input.targetLanguage,
  });

  pruneOldHistory();

  return { id, createdAt, imagePath };
}

export interface HistoryRecord {
  id: string;
  createdAt: string;
  imagePath: string;
  imageMimeType: string;
  originalText: string;
  translatedText: string;
  model: string;
  inputTokens: number | null;
  outputTokens: number | null;
  cacheCreationInputTokens: number | null;
  cacheReadInputTokens: number | null;
  sourceLanguage: string | null;
  targetLanguage: string | null;
}

const listStmt = db.prepare(`
  SELECT id, createdAt, imagePath, imageMimeType, originalText, translatedText, model,
         inputTokens, outputTokens, cacheCreationInputTokens, cacheReadInputTokens,
         sourceLanguage, targetLanguage
  FROM history
  ORDER BY createdAt DESC
`);

const getStmt = db.prepare(`
  SELECT id, createdAt, imagePath, imageMimeType, originalText, translatedText, model,
         inputTokens, outputTokens, cacheCreationInputTokens, cacheReadInputTokens,
         sourceLanguage, targetLanguage
  FROM history
  WHERE id = ?
`);

export function listHistory(): HistoryRecord[] {
  return listStmt.all() as HistoryRecord[];
}

export function getHistoryById(id: string): HistoryRecord | null {
  return (getStmt.get(id) as HistoryRecord | undefined) ?? null;
}

export function resolveImageAbsolutePath(imagePath: string): string {
  return join(dataDir, imagePath);
}
