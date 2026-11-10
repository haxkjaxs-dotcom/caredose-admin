// Runs the Supabase SQL in PGlite (Postgres in WASM), then every supabase/tests/[1-9]*.sql in name order.
import { PGlite } from '@electric-sql/pglite';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { dirname, join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const tests = dirname(fileURLToPath(import.meta.url));
const supabase = join(tests, '..');
const files = [
  join(tests, '00_auth_stub.sql'),
  join(supabase, 'schema.sql'),
  join(supabase, 'security_fixes.sql'),
  ...(existsSync(join(supabase, 'integration.sql')) ? [join(supabase, 'integration.sql')] : []),
  // security_fixes.sql says "safe to re-run": apply it again so every test also proves the two files converge
  join(supabase, 'security_fixes.sql'),
  ...readdirSync(tests).filter((f) => /^[1-9].*\.sql$/.test(f)).sort().map((f) => join(tests, f)),
];

const db = new PGlite();
db.onNotice?.((n) => console.log(`    notice: ${n.message}`));
let failed = false;
for (const file of files) {
  const name = relative(dirname(supabase), file).split(sep).join('/');
  try {
    await db.exec(readFileSync(file, 'utf8'));
    console.log(`ok   ${name}`);
  } catch (e) {
    console.error(`FAIL ${name}: ${e.message}`);
    failed = true;
    break;
  }
}
await db.close();
process.exit(failed ? 1 : 0);
