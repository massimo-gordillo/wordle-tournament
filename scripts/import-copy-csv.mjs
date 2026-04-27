import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  parseCsvRows,
  readCopyEntries,
  resolveCopyPath,
  writeCopyEntries,
} from './copy-csv-lib.mjs';

function parseArgs(argv) {
  const args = { file: null, column: null };
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token.startsWith('--file=')) {
      args.file = token.slice('--file='.length);
      continue;
    }
    if (token.startsWith('--column=')) {
      args.column = token.slice('--column='.length);
      continue;
    }
    if (token === '--file') {
      args.file = argv[index + 1] ?? null;
      index += 1;
      continue;
    }
    if (token === '--column') {
      args.column = argv[index + 1] ?? null;
      index += 1;
      continue;
    }
    if (!token.startsWith('-')) {
      if (!args.file) {
        args.file = token;
      } else if (!args.column) {
        args.column = token;
      }
    }
  }
  return args;
}

async function main() {
  const currentFilePath = fileURLToPath(import.meta.url);
  const projectRoot = path.resolve(path.dirname(currentFilePath), '..');
  const { file, column } = parseArgs(process.argv.slice(2));
  if (!file || !column) {
    throw new Error('Usage: node scripts/import-copy-csv.mjs --file <relative/path.csv> --column <columnName>');
  }

  const inputPath = path.resolve(projectRoot, file);
  const csvContent = await fs.readFile(inputPath, 'utf8');
  const rows = parseCsvRows(csvContent);
  const [header, ...dataRows] = rows;

  const keyIndex = header.indexOf('key');
  const targetColumnIndex = header.indexOf(column);

  if (keyIndex === -1) {
    throw new Error("CSV is missing required 'key' column.");
  }
  if (targetColumnIndex === -1) {
    throw new Error(`CSV does not contain requested column '${column}'.`);
  }

  const importedByKey = new Map();
  for (const row of dataRows) {
    const key = row[keyIndex]?.trim();
    if (!key) continue;
    if (importedByKey.has(key)) {
      throw new Error(`CSV contains duplicate key '${key}'.`);
    }
    importedByKey.set(key, row[targetColumnIndex] ?? '');
  }

  const copyPath = resolveCopyPath(projectRoot);
  const template = await readCopyEntries(copyPath);
  const existingKeys = new Set(template.entries.map(entry => entry.key));
  const importedKeys = new Set(importedByKey.keys());

  const unknownKeys = [...importedKeys].filter(key => !existingKeys.has(key));
  if (unknownKeys.length > 0) {
    throw new Error(`CSV contains unknown keys not present in source: ${unknownKeys.join(', ')}`);
  }

  const missingKeys = [...existingKeys].filter(key => !importedKeys.has(key));
  if (missingKeys.length > 0) {
    throw new Error(`CSV is missing keys required by source: ${missingKeys.join(', ')}`);
  }

  let updatedCount = 0;
  const nextEntries = template.entries.map(entry => {
    const incoming = importedByKey.get(entry.key);
    if (incoming == null || incoming === '') {
      return entry;
    }
    if (incoming !== entry.value) {
      updatedCount += 1;
    }
    return { ...entry, value: incoming };
  });

  await writeCopyEntries(copyPath, template, nextEntries);
  console.log(`Imported column '${column}' from ${inputPath}`);
  console.log(`Updated ${updatedCount} copy values (blank cells kept existing text).`);
}

main().catch(error => {
  console.error('Failed to import copy CSV:', error.message);
  process.exitCode = 1;
});
