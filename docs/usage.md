# Usage

With cmangos-deploy, you choose Docker images for an expansion, extract the
client data, run CMaNGOS with Docker Compose, and update it to get the latest
CMaNGOS changes. The sections below describe each step in detail, and the tasks
around them, such as backups. The [Docker Compose reference](compose.md)
explains the settings. Every example uses Classic; for another expansion,
replace `classic` with `tbc` or `wotlk`.

## Choosing images

### Expansions

cmangos-deploy builds a server image and a database image for each expansion
that CMaNGOS supports, each from the tip of that expansion's `master` branches:

| Expansion          | Server image                               | Database image                               |
| ------------------ | ------------------------------------------ | -------------------------------------------- |
| Classic (`1.12.1`) | `ghcr.io/mserajnik/cmangos-server-classic` | `ghcr.io/mserajnik/cmangos-database-classic` |
| TBC (`2.4.3`)      | `ghcr.io/mserajnik/cmangos-server-tbc`     | `ghcr.io/mserajnik/cmangos-database-tbc`     |
| WotLK (`3.3.5a`)   | `ghcr.io/mserajnik/cmangos-server-wotlk`   | `ghcr.io/mserajnik/cmangos-database-wotlk`   |

Each expansion has its own example Compose file, its own configuration
directory under [`config/`](../config), and its own storage directory under
[`storage/`](../storage).

### Pinning a specific CMaNGOS build

Each image has a tag that names the three commits of its build, the core, the
database, and Playerbot, as 7-character prefixes, such as
`classic-core.8ec338a-db.ec4f596-playerbots.1bafc21`. Use such tags to pin your
setup to a specific build. You have to give the server and the database image
the same tag, so the code and the data match. The databases apply new
migrations on start, so an image older than the ones you ran before cannot work
with them.

Since the Docker images are generally built only once a day, there is likely no
build for every single CMaNGOS commit combination. Older images are deleted
automatically after 14 days, so do not rely on the registry keeping a specific
image after you first pulled it. If you need images based on specific CMaNGOS
commits, you can build them yourself. The registry lists the current
[images][image-cmangos-packages].

## Client data

The server needs data extracted from the game client for handling movement and
line of sight. Use the client version that CMaNGOS supports for your chosen
expansion, as the [expansions section](#expansions) lists.

### Extracting the client data

Copy the contents of your client directory into
`storage/classic/mangosd/client-data/`. Then, to extract the data, run:

```sh
docker compose run --rm extract-client-data
```

The command runs the image of the `mangosd` service as its user (see the
[`extract-client-data` section](compose.md#extract-client-data)), so it
extracts for your chosen expansion.

The extraction can take many hours, and it prints some notices and errors while
it runs that are normal as long as the command does not end with an error. The
data ends up in `storage/classic/mangosd/extracted-data/`.

If you already have extracted data from another source, put it into
`storage/classic/mangosd/extracted-data/`. You can then skip the extraction.

To extract again later, for example after CMaNGOS improves the movement data,
run the same command. It asks before it overwrites the old data. To skip the
question, add `--force` at the end of the command.

## Running CMaNGOS

To start CMaNGOS, run:

```sh
docker compose up -d
```

The first start takes longer, because it creates the databases, and Playerbot
sets up its accounts and characters.

> [!WARNING]
> Do not interrupt the first start. If it stops early and the next start of the
> `database` service fails, remove the database volume with
> `docker compose down -v`, and start again.

To follow the server output, run:

```sh
docker compose logs -f mangosd
```

The server is ready when it prints `CMANGOS: World initialized`.

To stop CMaNGOS, run:

```sh
docker compose down
```

## Accounts

To create an account, attach to the server console once the server is ready:

```sh
docker compose attach mangosd
```

Then create the account and give it an account level:

```text
account create <account-name> <password>
account set gmlevel <account-name> <level>
```

| Level | Type          |
| ----- | ------------- |
| `0`   | Player        |
| `1`   | Moderator     |
| `2`   | Game Master   |
| `3`   | Administrator |

On TBC and WotLK, an account also needs an expansion level to reach that
expansion's content. New accounts get `0`, Classic. To raise it, run:

```text
account set addon <account-name> <level>
```

| Level | Expansion |
| ----- | --------- |
| `0`   | Classic   |
| `1`   | TBC       |
| `2`   | WotLK     |

To leave the console again, press <kbd>Ctrl</kbd>+<kbd>P</kbd> and then
<kbd>Ctrl</kbd>+<kbd>Q</kbd>. You can then log in with the account you created.

> [!NOTE]
> From level `1` up, characters on the account get some Game Master behavior,
> depending on the level. The `GM.*` options in your
> `config/classic/mangosd.conf` adjust some of it.

## Connecting a client

The game client reads the address of the login server from `realmlist.wtf`,
which is in the client directory for Classic and TBC, and in `Data/<locale>/`
for WotLK, such as `Data/enUS/realmlist.wtf`. To play on the host itself, set
it to:

```text
set realmlist 127.0.0.1
```

To connect from another machine, use the host's LAN address, WAN address, or
domain name instead. Set `CMANGOS_REALMLIST_ADDRESS` in your `compose.yaml` to
the same address, because the client receives the address of the world server
from the realm list.

## Playerbot and AHBot

The server images contain [Playerbot][playerbots] and AHBot. Playerbot lets you
add bots from characters on your own account and can fill the world with
computer-controlled players. AHBot buys and sells in the auction house. The
example configuration files turn off the automatic parts:

- `AiPlayerbot.RandomBotAutologin = 0` in your
  `config/classic/aiplayerbot.conf` keeps random bots from logging in. Players
  can still add bots with the in-game commands.
- `AuctionHouseBot.Chance.Sell = 0` and `AuctionHouseBot.Chance.Buy = 0` in
  your `config/classic/ahbot.conf` keep AHBot from trading.

To turn them on, change these options. The configuration files describe them.

## Updating

To update, pull the new images and check them:

```sh
docker compose pull
docker compose run --rm check-deploy-version
```

When the new images need configuration adjustments due to a
[breaking change](breaking-changes.md), the check fails and names the version
they expect. Make those adjustments first. The check reads
`CMANGOS_DEPLOY_VERSION` of `mangosd`, so keep the number the same in every
service.

If the check passes and prints that the variable matches, re-create the
containers:

```sh
docker compose up -d
```

If you pinned your setup to a specific build, the update only takes effect once
you set newer tags.

On the first start after an update, the `database` service applies the new
migrations to the databases. If a migration fails, the `database` service logs
the error, and its automatic restart counts the migration as applied. The cause
is a bug or something in your setup. Check the log for what failed, and decide
for yourself how to continue. You likely have to restore a backup from before
the update: remove the database volume with `docker compose down -v`, start
again, and restore the backup as the
[restoring a backup section](#restoring-a-backup) shows.

### Updating your clone

Update your clone of this repository regularly with `git pull`, and always
before you apply a breaking change, so you have the updated example Compose
files to compare with.

> [!IMPORTANT]
> The relaunch replaced the history of this repository, so `git pull` fails in
> a clone from before 2026-10-04. To update such a clone once, run `git fetch`
> and then `git reset --hard origin/master` in it. That keeps your
> `compose.yaml`, `config/`, and `storage/`, which Git ignores, but discards
> any edit you made to the repository's own files. Afterwards, `git pull` works
> again.

Most other changes are maintenance or new CMaNGOS options that you may want in
your configuration.

## Migration edits

Sometimes, upstream edits a migration that your databases have already applied.
The database cannot apply such a change again, so cmangos-deploy detects these
edits and acts on them.

- For the world database, the `database` service re-creates it from the new
  image. Changes you made directly in the world database are lost, such as your
  own NPCs or `npc_vendor` edits. Keep such changes as
  [custom SQL](#custom-sql), which the database runs again after the
  re-creation.
- A database with player data cannot be re-created. For those, the start halts
  and asks you to apply the change by hand, as the next section describes.

The [`database` section](compose.md#database) of the Docker Compose reference
describes the two variables that control this.

### Applying changes by hand

When the start halts, the `database` service prints the affected databases and
the link to each upstream commit. `realmd` and `mangosd` wait for the database,
so `docker compose up -d` keeps waiting too. Read the message from a second
terminal:

```sh
docker compose logs database
```

The container waits as long as you need. To resolve the halt:

1. Open each linked commit and read its changes to the SQL files.
2. Apply the same changes to each affected database, with the name in
   parentheses in the message. To open a database, run:

   ```sh
   docker compose exec database mariadb -u root -p <database>
   ```

   The password is `MARIADB_ROOT_PASSWORD` from your `compose.yaml`.
3. Once you have applied every change, confirm:

   ```sh
   docker compose exec database cmangos-confirm-changes
   ```

The start then records the commits as applied and continues. To give up on the
start, run `docker compose down`.

> [!WARNING]
> The confirmation marks the listed commits as applied without checking your
> database. If your change is wrong or incomplete, the database stays
> inconsistent, and CMaNGOS may fail to start. Matching what the commits do is
> your responsibility.

## Custom SQL

To make your own changes to the world database, put them into `.sql` files in
`storage/classic/database/custom-sql/`. The `database` service runs every file
there in alphabetical order on every start, after the migrations, and after a
re-creation of the world database too. So the statements have to be idempotent:
running them twice has to give the same result as running them once.

## Backups

Back up the databases regularly, especially before updating. The
`database-backup` service in your `compose.yaml` does it daily once you
uncomment it (see the
[`database-backup` section](compose.md#database-backup-optional)).

> [!NOTE]
> The Compose file leaves the world and logs databases out of the
> `database-backup` service, because most personal setups likely do not care
> enough about their contents to accept much larger backups. Apart from changes
> you make to it yourself, the image can re-create the world database. The logs
> database stores what the servers log to it. To back up either, add `mangos`
> or `logs` to `DB_DUMP_INCLUDE`.

To create a backup right away, run:

```sh
docker compose run --rm -e DB_DUMP_CRON= -e DB_DUMP_ONCE=true database-backup
```

The empty `DB_DUMP_CRON` is needed, because the service cannot combine a
schedule with a one-off run.

### Restoring a backup

A restore drops and re-creates the tables of each database in the backup. To
restore one:

1. Stop the servers, which would otherwise read and write the tables while they
   change:

   ```sh
   docker compose stop realmd mangosd
   ```

2. Restore the backup, with its file name from
   `storage/classic/database/backups/`:

   ```sh
   docker compose run --rm database-backup restore --target /backup \
     <backup-file>
   ```

3. Restart the database, which applies the migrations the backup lacks and
   writes the realm entry again, then start the servers:

   ```sh
   docker compose restart database
   docker compose start realmd mangosd
   ```

   If the backup is older than a migration edit, the restart handles the edit
   again, as the [migration edits section](#migration-edits) describes.

## Database access

Some tasks, such as managing accounts or changing the realm entry, need a
MariaDB client. The `phpmyadmin` service in your `compose.yaml` provides one in
the browser once you uncomment it (see the
[`phpmyadmin` section](compose.md#phpmyadmin-optional)).

### Database security

Do not expose the database to the internet, whether through a port mapping, a
phpMyAdmin instance, or anything else. If you expose it anyway, you are
responsible for securing it. cmangos-deploy does not support such a setup.

> [!CAUTION]
> The `root` user and the user from `MARIADB_USER` have full access to all
> CMaNGOS data, from any address.

[image-cmangos-packages]: https://github.com/mserajnik?tab=packages&repo_name=cmangos-deploy
[playerbots]: https://github.com/cmangos/playerbots
