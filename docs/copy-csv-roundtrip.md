# Copy CSV Roundtrip

This project supports a one-time manual copy handoff workflow:

1. Export all managed copy keys to CSV.
2. Send CSV to client.
3. Client fills in a custom column.
4. Import that column back into app copy.

## Source Of Truth

Managed copy is stored in `app/copy/strings.ts` as flat key/value entries between:

- `// COPY_ENTRIES_START`
- `// COPY_ENTRIES_END`

Do not change key names after sending CSV to the client.

## Export CSV

```bash
npm run copy:export:csv
```

Default output: `scripts/copy-export.csv`

Optional custom output path:

```bash
node scripts/export-copy-csv.mjs path/to/output.csv
```

## Client Editing Rules

- Keep the `key` column unchanged.
- Keep the `default` column as reference.
- Add a new column name (example: `client_v1`) and place edits there.
- Blank cells are allowed and keep existing app copy on import.

## Import Selected Column

```bash
npm run copy:import:csv -- --file scripts/copy-export.csv --column client_v1
```

Import validations:

- fails if `key` column is missing,
- fails if selected column does not exist,
- fails on duplicate keys,
- fails if CSV has unknown keys or is missing required keys.

After import, app copy updates in `app/copy/strings.ts`.
