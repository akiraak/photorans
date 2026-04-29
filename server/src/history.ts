import Database from 'better-sqlite3';
import { mkdirSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { randomUUID } from 'node:crypto';

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
    model TEXT NOT NULL
  );
  CREATE INDEX IF NOT EXISTS idx_history_createdAt ON history(createdAt DESC);
`);

const insertStmt = db.prepare(`
  INSERT INTO history (id, createdAt, imagePath, imageMimeType, originalText, translatedText, model)
  VALUES (@id, @createdAt, @imagePath, @imageMimeType, @originalText, @translatedText, @model)
`);

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
  model: string;
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
  });

  return { id, createdAt, imagePath };
}
