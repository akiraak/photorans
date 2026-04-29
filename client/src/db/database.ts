import { openDatabaseSync, type SQLiteDatabase } from 'expo-sqlite';

export type HistoryRecord = {
  id: string;
  createdAt: string;
  imageUri: string;
  imageMimeType: string;
  originalText: string;
  translatedText: string;
  model: string;
};

let dbInstance: SQLiteDatabase | null = null;

function getDb(): SQLiteDatabase {
  if (dbInstance) return dbInstance;
  const db = openDatabaseSync('photorans.db');
  db.execSync(`
    CREATE TABLE IF NOT EXISTS history (
      id TEXT PRIMARY KEY,
      createdAt TEXT NOT NULL,
      imageUri TEXT NOT NULL,
      imageMimeType TEXT NOT NULL,
      originalText TEXT NOT NULL,
      translatedText TEXT NOT NULL,
      model TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS history_createdAt_idx ON history(createdAt DESC);
  `);
  dbInstance = db;
  return db;
}

export function insertHistory(record: HistoryRecord): void {
  getDb().runSync(
    `INSERT INTO history (id, createdAt, imageUri, imageMimeType, originalText, translatedText, model)
     VALUES (?, ?, ?, ?, ?, ?, ?)`,
    record.id,
    record.createdAt,
    record.imageUri,
    record.imageMimeType,
    record.originalText,
    record.translatedText,
    record.model,
  );
}

export function listHistory(): HistoryRecord[] {
  return getDb().getAllSync<HistoryRecord>(
    `SELECT id, createdAt, imageUri, imageMimeType, originalText, translatedText, model
     FROM history
     ORDER BY createdAt DESC`,
  );
}

export function getHistoryById(id: string): HistoryRecord | null {
  return getDb().getFirstSync<HistoryRecord>(
    `SELECT id, createdAt, imageUri, imageMimeType, originalText, translatedText, model
     FROM history
     WHERE id = ?`,
    id,
  );
}
