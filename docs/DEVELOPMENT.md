# Local development

Run from the checkout:

```sh
./scripts/dev.sh up
```

The launcher retrieves dependencies, verifies PostgreSQL authentication, creates
`fount_dev` if missing, applies Core → Run → host migrations, builds assets and
starts Phoenix at `http://127.0.0.1:4000/login`. Analysis uses simulated responses.
`setup` performs setup without starting Phoenix; `start` verifies the connection
and starts an already prepared checkout. The SDK defaults to its published Hex
requirement, without needing a sibling source checkout.

## PostgreSQL connection selection

1. `--database-url` overrides `FOUNT_DATABASE_URL`. An explicit URL is verified
   as supplied. Failure never redirects to another database or server.
2. Without a URL, the launcher first tries `PGHOST`, `PGPORT`, `PGUSER` and
   `PGPASSWORD` when present. A failed remote `PGHOST` never falls back locally.
3. For local discovery, it reads PostgreSQL socket names in `/var/run/postgresql`,
   `/run/postgresql`, `/tmp` and a socket directory supplied as `PGHOST`. It also
   reads online cluster ports using `pg_lsclusters` when available. Both standard
   port 5432 and discovered ports such as 5433 are supported. No `psql`, sudo,
   Docker or Debian cluster tooling is required for the driver probes themselves.
4. It verifies connections using Postgrex and existing credentials or the current
   operating-system role's socket authentication. Connections to the same server
   are deduplicated. Multiple usable servers require an explicit URL.
   Status is printed before probes. Local checks run concurrently: the preferred
   local connection has a 1.5-second deadline and the entire discovery scan has
   a 1.75-second deadline. Explicit URLs and remote connections get four seconds.
   Timed-out workers are terminated; no retry loop runs during discovery.

The default target database is `fount_dev`, independent of `PGDATABASE`. To select
another database, use an explicit URL. The role must be able to connect to that
existing database or create it through the `postgres` maintenance database.
Discovery only reads connection metadata. The launcher never creates roles,
changes passwords, changes PostgreSQL configuration, starts/stops clusters or
resets databases. Setup creates the target database and applies migrations.

For password-authenticated or remote servers, supply your existing connection
settings. SSL and other Ecto URL options are preserved. Credentials are never
printed by the connection probe or placed in its command arguments. The resolved
URL is passed through a temporary file readable only by the current user, removed
before Phoenix starts and on setup failure.

```sh
# Supply FOUNT_DATABASE_URL through your usual secret/environment mechanism.
./scripts/dev.sh up
# Explicit local socket connection, without a password:
./scripts/dev.sh up --database-url 'ecto://writer@localhost:5433/fount_dev?socket_dir=/var/run/postgresql'
# Choose an HTTP port independently of PostgreSQL's port:
./scripts/dev.sh up --port 4050
```

If authentication fails, configure an existing authorized role. If several
clusters are usable, select the intended cluster explicitly. Increasing pool size
or queue timeouts does not repair an unavailable or unauthenticated server.

At startup the default demo login token appears on its own line inside a large
terminal banner. Interactive terminals display it in bold; redirected output
remains plain text. Custom owner tokens remain private.
