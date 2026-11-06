# Usage

To run CMaNGOS, you choose Docker images for an expansion, extract the client
data, and start the server with Docker Compose. Later, you update it to get the
latest CMaNGOS changes. The sections below describe each step, and other tasks
such as creating accounts, making backups, and accessing the databases. The
[Docker Compose reference](compose.md) describes each setting in your
`compose.yaml`. Every example uses Classic; for another expansion, replace
`classic` with `tbc` or `wotlk`.

## Choosing images

### Expansions

cmangos-deploy builds a server image and a database image for each expansion
that CMaNGOS supports, from the tips of the `master` branches of the
expansion's core and world database and of the Playerbot module:

| Expansion          | Server image                               | Database image                               |
| ------------------ | ------------------------------------------ | -------------------------------------------- |
| Classic (`1.12.1`) | `ghcr.io/mserajnik/cmangos-server-classic` | `ghcr.io/mserajnik/cmangos-database-classic` |
| TBC (`2.4.3`)      | `ghcr.io/mserajnik/cmangos-server-tbc`     | `ghcr.io/mserajnik/cmangos-database-tbc`     |
| WotLK (`3.3.5a`)   | `ghcr.io/mserajnik/cmangos-server-wotlk`   | `ghcr.io/mserajnik/cmangos-database-wotlk`   |

Each expansion has its own example Compose file, its own configuration
directory under [`config/`](../config), and its own storage directory under
[`storage/`](../storage).

### Pinning a specific CMaNGOS build

Each image has a tag with the three commits of its build, from the repositories
of the core, the world database, and the Playerbot module, as 7-character
prefixes, such as `classic-core.8ec338a-db.ec4f596-playerbots.1bafc21`. Use
such tags to pin your installation to a specific build. You have to give the
server and the database image the same tag, so the code and the data match. The
`database` service applies new migrations when it starts, so an image older
than those you ran before cannot work with the databases.

Since the Docker images are generally built only once a day, there is likely no
build for every single CMaNGOS commit combination. Older images are deleted
automatically after 14 days, so do not rely on the registry keeping a specific
image after you first pulled it. If you need images based on specific CMaNGOS
commits, you can build them yourself. The registry lists the current
[images][image-cmangos-packages].

## Extracting the client data

The server needs data extracted from the game client for handling movement and
line of sight. Use the client version that CMaNGOS supports for your chosen
expansion, as the [expansions section](#expansions) lists.

Copy the contents of your client directory into
`storage/classic/mangosd/client-data/`. Then, to extract the data, run:

```sh
docker compose run --rm extract-client-data
```

The command runs the image of the `mangosd` service as its user (see the
[`extract-client-data` section](compose.md#extract-client-data)), so it
extracts for your chosen expansion.

The extraction writes the data into `storage/classic/mangosd/extracted-data/`
and can take many hours. It prints some notices and errors while it runs that
are normal as long as the command does not end with an error.

If you already have extracted data from another source, put it into
`storage/classic/mangosd/extracted-data/`. You can then skip the extraction.

You may want to extract again when CMaNGOS improves the extractors in some way.
To do so, run the same command. It asks before it overwrites the old data. To
skip the question, add `--force` at the end of the command.

## Anticheat and Warden

CMaNGOS's anticheat, including Warden, is enabled by default. The options in
your `config/classic/anticheat.conf` adjust or disable it.

> [!WARNING]
> Clients other than those that CMaNGOS targets, such as modern official
> versions that connect through a proxy and third-party re-implementations, are
> unlikely to work while Warden is enabled: the server disconnects a client
> that fails to answer its checks. To use such a client, set
> `Warden.Enable = 0` in your `config/classic/anticheat.conf`.

## Running CMaNGOS

To start CMaNGOS, run:

```sh
docker compose up -d
```

The first start takes longer, because it creates the databases, and Playerbot
sets up its accounts and characters.

> [!WARNING]
> Do not interrupt the first start. If it stops early and the `database`
> service then fails to start, remove the database volume with
> `docker compose down -v`, and run `docker compose up -d` again.

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
[breaking change](breaking-changes.md), the check fails and shows the version
they expect. Make those adjustments first. The `check-deploy-version` service
reads only `CMANGOS_DEPLOY_VERSION` of the `mangosd` service. The `database`,
`realmd`, and `mangosd` services also each check their own value when they
start, so you have to set the same number in all three.

If the check passes and prints that the variable matches, re-create the
containers:

```sh
docker compose up -d
```

If `docker compose up -d` keeps waiting for the `database` service, it has
likely halted for [migration edits](#migration-edits).

If you pinned your installation to a specific build, the update only takes
effect once you set newer tags.

After an update, the `database` service applies the new migrations when it
starts. If a migration fails, the `database` service logs the error and stops.
When Docker then restarts the container, the `database` service either counts
the migration as applied or runs it again. Which of the two happens depends on
the migration. The cause is a bug or something in your installation. Check the
log for what failed, and decide for yourself how to continue. You likely have
to restore a backup from before the update: remove the database volume with
`docker compose down -v`, run `docker compose up -d` again, and restore the
backup as the [restoring a backup section](#restoring-a-backup) shows.

### Updating your clone

Update your clone of this repository regularly with `git pull`, and always
before you apply a breaking change, so you have the updated example Compose
files to compare with. Most other changes are maintenance or new CMaNGOS
options that you may want in your configuration.

> [!IMPORTANT]
> The relaunch replaced the history of this repository, so `git pull` fails in
> a clone from before 2026-10-04. To update such a clone once, run `git fetch`
> and then `git reset --hard origin/master` in it. That keeps your
> `compose.yaml`, `config/`, and `storage/`, which Git ignores, but discards
> any edit you made to the repository's own files. Afterwards, `git pull` works
> again.

## Migration edits

Sometimes, the CMaNGOS developers edit a migration that has already been
applied to one of your databases. The `database` service does not apply an
edited migration again, so cmangos-deploy detects these edits and acts on them.

- For the world database, the `database` service re-creates it from the new
  image. Changes you made directly in the world database are lost, such as your
  own NPCs or `npc_vendor` edits. Keep such changes as
  [custom SQL](#custom-sql), which the `database` service runs again after the
  re-creation.
- A database with player data cannot be re-created. For such a database, the
  `database` service halts and asks you to apply the change by hand, as the
  next section describes.

The [`database` section](compose.md#database) of the Docker Compose reference
describes the two variables that control this.

### Applying changes by hand

During a halt, the `database` service prints the affected databases and the
link to the commit of each edit. Its healthcheck does not pass until you
confirm, and the `realmd` and `mangosd` services only start once it passes, so
`docker compose up -d` keeps waiting too. Read the message from a second
terminal:

```sh
docker compose logs database
```

> [!WARNING]
> The SQL you run here changes your databases directly. If something goes
> wrong, only a backup from before the update can restore them. The restore
> needs the `database` service to run normally, so confirm first, then follow
> the [restoring a backup section](#restoring-a-backup).

The `database` service waits as long as you need. To resolve the halt:

1. Open each linked commit and read its changes to the SQL files.
2. The message lists each edit with the database it affects. Make the edit's
   changes yourself in that database. The `database` service does not apply an
   edited migration again, so the database still matches the result of the old
   version. Compare the old and the new version of each edited file in the
   commit, and run the SQL that changes the database to the result of the new
   version.

   To open a database, run:

   ```sh
   docker compose exec database mariadb -u root -p <database>
   ```

   The password is `MARIADB_ROOT_PASSWORD` from your `compose.yaml`. The
   [MariaDB client documentation][mariadb-client] describes the client's
   commands. To leave the client, run `exit`.
3. Once you have handled every listed edit, confirm:

   ```sh
   docker compose exec database cmangos-confirm-changes
   ```

The `database` service then records the commits as applied and resumes. If the
halt lasted longer than the `start_period` of its healthcheck (24 hours in the
example Compose file), `docker compose up -d` has likely stopped with an error,
and you need to run it again to start the `realmd` and `mangosd` services.

> [!WARNING]
> The confirmation marks the listed commits as applied without checking your
> databases. If your change is wrong or incomplete, the affected database stays
> inconsistent, and CMaNGOS may fail to start. Matching what the commits do is
> your responsibility, and cmangos-deploy provides no further support for
> individual cases.

To stop the containers and handle the edits later, run `docker compose down`
without confirming. The `database` service halts again the next time it starts.

In a database with player data, you can ignore an edit to a migration that has
not been applied to it yet. How to check depends on where the migration comes
from:

- A versioned update in `sql/updates/<database>/`, such as
  `z2819_01_characters_item_instance_text_id_fix.sql`: the database records
  only the last versioned update applied to it, as the column name of its
  version table (`character_db_version`, `realmd_db_version`, or
  `logs_db_version`):

  ```sh
  docker compose exec database mariadb -u root -p <database> \
    -e "SELECT * FROM <version-table>"
  ```

  The column name contains the number of the last applied versioned update,
  such as `z2818_02` in `required_z2818_02_characters_...`. A versioned update
  with a higher number has not been applied: compare the part before the
  underscore first, such as `2819` against `2818`, and the part after it only
  when those are equal.
- A file of the Playerbot module in `sql/characters/`: the database records
  each applied file by its name, with `.sql`:

  ```sh
  docker compose exec database mariadb -u root -p <database> \
    -e "SELECT sql_key FROM cmangos_deploy_applied_sql \
      WHERE sql_key = 'playerbots-characters/<file-name>'"
  ```

  When the query returns no row, the file has not been applied.
- A change to a base dump, `sql/base/<database>.sql`: the `database` service
  imported this file only when it created the database. If the same commit adds
  a versioned update that has not been applied yet, that update usually makes
  the same change. Compare the two, and if the update covers every change to
  the base dump, you can ignore the edit. Otherwise, apply the rest by hand.

For a renamed migration, check its old file name.

Even when every listed edit can be ignored, you still have to confirm, as step
3 above describes.

## Custom SQL

To make your own changes to the world database, put them into `.sql` files in
`storage/classic/database/custom-sql/`. The `database` service runs each file
there in alphabetical order every time it starts, after the migrations, and
after a re-creation of the world database too. So the statements have to be
idempotent: running them twice has to give the same result as running them
once.

## Backups

Back up the databases regularly, especially before updating. The
`database-backup` service in your `compose.yaml` does it daily once you
uncomment it (see the
[`database-backup` section](compose.md#database-backup-optional)).

> [!NOTE]
> The example Compose file leaves the world and logs databases out of the
> `database-backup` service, because most personal installations likely do not
> care enough about their contents to accept much larger backups. Apart from
> changes you make to it yourself, the `database` service can re-create the
> world database. The logs database stores what the servers log to it. To back
> up either, add `mangos` or `logs` to `DB_DUMP_INCLUDE`.

To create a backup right away, run:

```sh
docker compose run --rm -e DB_DUMP_CRON= -e DB_DUMP_ONCE=true database-backup
```

The empty `DB_DUMP_CRON` is needed, because the service cannot combine a
schedule with a one-off run.

### Restoring a backup

A restore drops and re-creates the tables of each database in the backup. To
restore a backup:

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

3. Restart the `database` service, which applies the migrations the backup
   lacks and writes the realm entry again, then start the servers:

   ```sh
   docker compose restart database
   docker compose start realmd mangosd
   ```

   If the backup is older than a migration edit, the `database` service then
   acts on the edit again, as the [migration edits section](#migration-edits)
   describes.

## Database access

Some tasks, such as managing accounts or changing the realm entry, need a
MariaDB client. The `phpmyadmin` service in your `compose.yaml` provides a
client in the browser once you uncomment it (see the
[`phpmyadmin` section](compose.md#phpmyadmin-optional)).

### Database security

Do not expose the databases to the internet, whether through a port mapping, a
phpMyAdmin instance, or anything else. If you expose them anyway, you are
responsible for securing them. cmangos-deploy does not support such a setup.

> [!CAUTION]
> The `root` user and the user from `MARIADB_USER` have full access to all
> CMaNGOS data, from any address.

[image-cmangos-packages]: https://github.com/mserajnik?tab=packages&repo_name=cmangos-deploy
[mariadb-client]: https://mariadb.com/docs/server/clients-and-utilities/mariadb-client/mariadb-command-line-client
[playerbots]: https://github.com/cmangos/playerbots
