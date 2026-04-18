CREATE TABLE backups (
id TEXT PRIMARY KEY,
filename TEXT NOT NULL,
size INTEGER NOT NULL CHECK (size > 0),
sha256hash TEXT NOT NULL UNIQUE,
createdat TEXT NOT NULL,
format_valid BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE signingevents (
id TEXT PRIMARY KEY,
backupid TEXT NOT NULL REFERENCES backups(id),
signature TEXT NOT NULL,
keyversion TEXT NOT NULL,
signedat TEXT NOT NULL,
githubcommitsha TEXT NOT NULL,
status TEXT NOT NULL CHECK (status IN ('SUCCESS', 'FAILED'))
);

CREATE TABLE chainmanifest (
id TEXT PRIMARY KEY,
backupid TEXT NOT NULL REFERENCES backups(id),
chainhead TEXT NOT NULL,
githubpubkeyurl TEXT NOT NULL,
timestamprfc3339nano TEXT NOT NULL,
manifestjson TEXT NOT NULL,
createdat TEXT NOT NULL
);
