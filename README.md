<h1>
  <img src=".github/logo.png" alt="" height="100" align="center">
  cmangos-deploy
</h1>

[![Latest Classic build][badge-latest-classic-build]][badge-latest-classic-build-url]\
[![Latest TBC build][badge-latest-tbc-build]][badge-latest-tbc-build-url]\
[![Latest WotLK build][badge-latest-wotlk-build]][badge-latest-wotlk-build-url]\
[![Latest build date][badge-latest-build-date]][badge-latest-build-date-url]
[![GitHub Actions status][badge-actions-status]][badge-actions-status-url]

> A Docker setup for CMaNGOS

This is a Docker-based solution for running [CMaNGOS][cmangos] that focuses on
providing a streamlined and user-friendly experience. It is largely based on
[vmangos-deploy][vmangos-deploy] and offers a range of features that simplify
managing a CMaNGOS setup:

- __Prebuilt Docker images for both `amd64` and `arm64`, leveraging GitHub__
  __Actions:__ simply pull the provided images that have been optimized for
  size, performance and stability instead of having to re-compile CMaNGOS
  yourself every time you want to update
- __Support for all three CMaNGOS expansions:__ Classic, TBC and WotLK are each
  available as separate prebuilt images
- __Built-in [Playerbots][playerbots] support:__ bots can be spawned on demand,
  or they can populate the world automatically
- __Seamless, automated database migrations:__ when pulling the latest Docker
  images and re-creating the containers, migrations are applied automatically
  to keep your database up-to-date at all times
- __A transparent and easy-to-follow user experience:__ the number of different
  commands that need to be run to install and manage CMaNGOS is kept to a
  minimum. You can use the Docker CLI or any other tool that is able to manage
  Docker containers
- __A clean and organized structure:__ the CMaNGOS configuration for each
  expansion can be found in [`./config/<expansion>`](config), everything else
  that is shared between the Docker containers and your host system lives
  inside [`./storage/<expansion>`](storage)

> [!NOTE]
> The Docker images are built on a daily schedule, unless there have been no
> new commits to CMaNGOS since the last build. Additionally, every Monday, the
> latest images are rebuilt to ensure software and dependencies are up-to-date,
> even if there have been no updates to CMaNGOS itself.

## Table of contents

- [Install](#install)
  - [Dependencies](#dependencies)
  - [Using a coding agent](#using-a-coding-agent)
  - [Instructions](#instructions)
    - [Cloning the repository and adjusting the CMaNGOS configuration](#cloning-the-repository-and-adjusting-the-cmangos-configuration)
    - [Adjusting the Docker Compose configuration](#adjusting-the-docker-compose-configuration)
    - [Extracting the client data](#extracting-the-client-data)
    - [Modifying the world database with custom changes (optional)](#modifying-the-world-database-with-custom-changes-optional)
- [Usage](#usage)
  - [Starting CMaNGOS](#starting-cmangos)
  - [Observing the CMaNGOS output](#observing-the-cmangos-output)
  - [Creating the first account](#creating-the-first-account)
  - [Stopping CMaNGOS](#stopping-cmangos)
  - [Updating](#updating)
    - [What happens during an update](#what-happens-during-an-update)
    - [When cmangos-deploy asks you to apply changes manually](#when-cmangos-deploy-asks-you-to-apply-changes-manually)
  - [Creating database backups](#creating-database-backups)
  - [Accessing the database](#accessing-the-database)
  - [Database security](#database-security)
- [Maintainer](#maintainer)
- [Contribute](#contribute)
- [License](#license)

## Install

### Dependencies

- [Docker][docker] (including [Compose V2][docker-compose])

### Using a coding agent

If you have a coding agent like [Claude Code][claude-code] or [Codex][codex]
installed, you can try a prompt similar to the following one to have it assist
you with the installation process:

```
Help me install and set up https://github.com/mserajnik/cmangos-deploy.
First, clone the repository and read the README carefully.
Then guide me through the installation process step by step, following the
README closely.
Do as much of the setup yourself as you safely can so that I only have to step
in when a manual action or personal preference is required.
Ask me about my preferences whenever a choice has to be made, explain the
relevant options clearly, and tailor your instructions to the OS I am using.
Assume that I am not familiar with CMaNGOS or Docker and that I have not read
the README myself.
For steps that I need to perform manually, give me clear instructions and exact
commands where appropriate.
Do not assume user-facing choices such as the expansion, optional services, or
networking-related preferences. Ask me whenever the README presents a
meaningful choice.
For settings that the README, the Docker Compose configuration, or the CMaNGOS
example configuration files indicate should generally be left alone, keep the
documented defaults unless I explicitly ask for something else.
Do not change settings that the README, the Docker Compose configuration, or
the CMaNGOS example configuration files indicate should not be changed.
```

The exact prompt that works best may vary depending on the coding agent and
model you use.

> [!CAUTION]
> You use coding agents at your own risk. You are responsible for the
> permissions and access you give them. The maintainer of this project is not
> liable for any damage or data loss resulting from their use. Take appropriate
> precautions such as sandboxed access and limited permissions, and do not run
> them with `--yolo` or similar options that bypass safety checks.

### Instructions

#### Cloning the repository and adjusting the CMaNGOS configuration

First, clone the repository:

```sh
git clone https://github.com/mserajnik/cmangos-deploy.git
cd cmangos-deploy
```

cmangos-deploy supports three expansions, each with its own configuration
directory under [`./config`](config):

- [`./config/classic`](config/classic) for Classic
- [`./config/tbc`](config/tbc) for TBC
- [`./config/wotlk`](config/wotlk) for WotLK

Pick the one matching the expansion you want to run and create copies of the
provided CMaNGOS example configuration files in that directory. For example,
for Classic:

```sh
cp ./config/classic/mangosd.conf.example ./config/classic/mangosd.conf
cp ./config/classic/realmd.conf.example ./config/classic/realmd.conf
cp ./config/classic/ahbot.conf.example ./config/classic/ahbot.conf
cp ./config/classic/aiplayerbot.conf.example ./config/classic/aiplayerbot.conf
cp ./config/classic/anticheat.conf.example ./config/classic/anticheat.conf
cp ./config/classic/mods.conf.example ./config/classic/mods.conf
```

For TBC and WotLK, the same applies with `tbc` or `wotlk` substituted for
`classic`. Note that `mods.conf.example` only ships for Classic; it does not
exist for TBC or WotLK.

Next, adjust the configuration files you have just created for your desired
setup. The default configuration should work well as a starting point, but you
may still want to adjust certain things such as the `GameType`, the `RealmZone`
or `Anticheat.*` and `Warden.*` options. Descriptions are provided for each
option in the configuration files, so you should be able to find your way
around easily.

> [!NOTE]
> The bundled `aiplayerbot.conf.example` disables auto-spawning random bots by
> default (`AiPlayerbot.RandomBotAutologin = 0`) and the bundled
> `ahbot.conf.example` disables AHBot by default
> (`AuctionHouseBot.Chance.Sell = 0` and `AuctionHouseBot.Chance.Buy = 0`).
> Both can be re-enabled by adjusting the marked options. Players can still
> spawn bots manually via the in-game command regardless.

> [!CAUTION]
> Options relating to certain things that cmangos-deploy relies on to work
> correctly (like the database connections or configured directories such as
> the `DataDir` or the `LogsDir`) should not be adjusted unless you absolutely
> need to change them and are aware of the implications (e.g., which other
> configuration options may need to be adjusted as well to avoid discrepancies
> resulting in unexpected behavior). No support will be provided for
> non-default setups.

#### Adjusting the Docker Compose configuration

Once you are done adjusting the CMaNGOS configuration, copy the Docker Compose
example file for your chosen expansion to `compose.yaml`. For example, for
Classic:

```sh
cp ./compose-classic.yaml.example ./compose.yaml
```

For TBC and WotLK, use `compose-tbc.yaml.example` or
`compose-wotlk.yaml.example` instead. The three files share the same structure
and only differ where the expansion makes them.

The available images for each expansion are:

| Expansion          | Server image                               | Database image                               |
| ------------------ | ------------------------------------------ | -------------------------------------------- |
| Classic (`1.12.1`) | `ghcr.io/mserajnik/cmangos-server-classic` | `ghcr.io/mserajnik/cmangos-database-classic` |
| TBC (`2.4.3`)      | `ghcr.io/mserajnik/cmangos-server-tbc`     | `ghcr.io/mserajnik/cmangos-database-tbc`     |
| WotLK (`3.3.5a`)   | `ghcr.io/mserajnik/cmangos-server-wotlk`   | `ghcr.io/mserajnik/cmangos-database-wotlk`   |

By default, the latest available images are used. Alternatively, you can also
select specific ones via their combined revision tag. Each image is tagged with
a tag of the form
`<expansion>-core.<core-revision>-db.<db-revision>-playerbots.<playerbots-revision>`,
where each revision is a 12-character prefix of the matching commit hash. For
example, a Classic build might have the tag
`classic-core.1aea167db349-db.2c980fa2175c-playerbots.c33dfac220eb` on both the
server and database images.

> [!IMPORTANT]
> When you decide to select images via combined revision tag you should always
> make sure to use the same one for the `cmangos-server-<expansion>` and the
> `cmangos-database-<expansion>` images so there are no potential discrepancies
> between code and data. It is _not_ possible (or intended) to switch to images
> based on older revisions than the previous ones you used to perform a clean
> downgrade due to the database migrations.

Since the Docker images are generally built only once a day, it is unlikely
that there will be a build for every single CMaNGOS commit. Older images are
automatically deleted, roughly after 40 days; in practice, you should not rely
on specific images staying available for any prolonged period of time. If you
absolutely need images based on a specific commit, you can always build them
yourself instead.

> [!TIP]
> You can find all the currently available `cmangos-server-<expansion>` and
> `cmangos-database-<expansion>` images by browsing the packages listed
> [here][image-cmangos-packages].

Aside from which Docker images you want to use you mainly have to pay attention
to the `environment` sections of each service configuration. In particular, you
will want to adjust the `TZ` (time zone) environment variable for each service.
The `CMANGOS_REALMLIST_*` environment variables of the `database` service
should also be of interest; changing the `CMANGOS_REALMLIST_ADDRESS` to a LAN
IP, a WAN IP or a domain name is required if you want to allow non-local
connections.

Also take note of the `healthcheck` sections; if you are using a low end system
you may have to adjust the `start_period` setting so that the initial database
creation process will be able to complete in time before the healthcheck
considers the container unhealthy and causes a restart.

> [!CAUTION]
> Anything in your `compose.yaml` that is not commented or explicitly mentioned
> in this README, regardless of the section, is likely something you do not
> have to (or, in some cases, _must not_) change. Doing so may lead to
> unexpected behavior and is not supported.

#### Extracting the client data

CMaNGOS uses data that is generated from extracted client data to handle things
like mob movement and line of sight. If you have already acquired this data
previously, you can place it directly into
`./storage/<expansion>/mangosd/extracted-data` and skip the next steps.

To extract the data, first copy the contents of your client directory into
`./storage/<expansion>/mangosd/client-data`. Next, run the following command,
substituting the image for the expansion you want to extract for. For example,
for Classic:

```sh
docker run \
  -i \
  -v ./storage/classic/mangosd/client-data:/opt/cmangos/storage/client-data \
  -v ./storage/classic/mangosd/extracted-data:/opt/cmangos/storage/data \
  --rm \
  --user 1000:1000 \
  --platform linux/amd64 \
  ghcr.io/mserajnik/cmangos-server-classic \
  extract-client-data
```

There are two things to look out for here:

- If you are using a Linux host and your user's UID and GID are not 1000,
  change the `--user` argument to reflect your user's UID and GID. This will
  cause the user in the container to use the same UID and GID and prevent
  permission issues on the bind mounts. If you are on Windows or macOS, you can
  ignore this (or even remove the `--user` argument altogether, if you want to)
- The Docker image must reflect the expansion you want to extract the data for

> [!IMPORTANT]
> The extractors are only included in the `amd64` images because CMaNGOS forces
> `BUILD_EXTRACTORS=OFF` on `arm64`. The `--platform linux/amd64` flag in the
> command above ensures the right image variant is used even on `arm64` hosts
> (running through emulation, which can be slow).
>
> Extracting the data can take many hours (depending on your hardware). Some
> notices/errors during the process are normal and usually nothing to worry
> about (as long as the execution continues afterwards).

Once the extraction is finished you can find the data in
`./storage/<expansion>/mangosd/extracted-data`. Note that you may want to
re-run the process in the future if CMaNGOS makes changes (to benefit from
potentially improved mob movement etc.).

If you re-run the extraction, it will automatically detect previously extracted
data and ask you if you want to continue (which will overwrite the old data).
You can also skip this confirmation prompt (and force the re-extraction) by
adding the `--force` flag to the `extract-client-data` command, like this:

```sh
docker run \
  -i \
  -v ./storage/classic/mangosd/client-data:/opt/cmangos/storage/client-data \
  -v ./storage/classic/mangosd/extracted-data:/opt/cmangos/storage/data \
  --rm \
  --user 1000:1000 \
  --platform linux/amd64 \
  ghcr.io/mserajnik/cmangos-server-classic \
  extract-client-data --force
```

#### Modifying the world database with custom changes (optional)

If you want to make custom changes to the world database, it is recommended to
do so using SQL files and placing them in
`./storage/<expansion>/database/custom-sql` (a bind mount for this directory is
[configured out-of-the-box][compose-custom-sql-bind-mount]). The files in this
directory are processed on every startup, including after cmangos-deploy
re-creates the world database to apply an upstream migration edit (see the
_[What happens during an update](#what-happens-during-an-update)_ section), so
your changes survive that flow without manual intervention.

By default, all SQL files (files with a `.sql` extension) in that directory
will be processed during each startup in alphabetical order (after the world
database has been created and updated with the latest migrations). Thus, the
SQL statements in your files have to be idempotent (i.e., they can be processed
multiple times without causing issues).

You can find further details about this feature [here][compose-custom-sql].

## Usage

### Starting CMaNGOS

Once you are happy with the configuration and have extracted the client data,
you can start CMaNGOS for the first time. To do so, run:

```sh
docker compose up -d
```

This pulls the Docker images first and afterwards automatically creates and
starts the containers. During the first startup it might take a little longer
until the server becomes available due to the initial database creation.

> [!CAUTION]
> Make sure to not (accidentally) stop CMaNGOS before the database creation
> process has finished; otherwise, you will likely end up with a broken
> database and will have to delete and re-create it.

### Observing the CMaNGOS output

Especially during the first startup you might want to follow the server output
to know when CMaNGOS is up and running:

```sh
docker compose logs -f mangosd
```

Once you see the output `World initialized.` you know that the initialization
process has finished and CMaNGOS is ready.

### Creating the first account

To create the first account, attach to the `mangosd` container (make sure
[that the server is ready](#observing-the-cmangos-output) before attaching):

```sh
docker compose attach mangosd
```

After attaching, create the account and assign an account level:

```sh
account create <account name> <account password>
account set gmlevel <account name> <account level>
```

The available account levels are:

| Level | Type          |
| ----- | ------------- |
| `0`   | Player        |
| `1`   | Moderator     |
| `2`   | Game Master   |
| `3`   | Administrator |

E.g., to create an administrator account, set the account level to `3`.

> [!NOTE]
> Setting an account level of `1` or higher means that some Game
> Master-specific behavior will begin to apply to characters on that account.
> Exactly which behavior applies depends on the account level; you can modify
> some of this via the [`GM.*` options][mangosd-gm-options] in your
> `mangosd.conf`.

For TBC and WotLK, expansion-specific content is gated by an "expansion level"
that has to be set per account. New accounts default to level `0`, which
corresponds to Classic. To unlock expansion content, run:

```sh
account set addon <account name> <expansion level>
```

The available expansion levels are:

| Expansion | Level | Effect                      |
| --------- | ----- | --------------------------- |
| Classic   | `0`   | Default; no action required |
| TBC       | `1`   | Unlocks TBC content         |
| WotLK     | `2`   | Unlocks WotLK content       |

When you are done, detach from the Docker container by pressing
<kbd>Ctrl</kbd>+<kbd>P</kbd> and <kbd>Ctrl</kbd>+<kbd>Q</kbd>. You should now
be able to log in to the game client with your newly created account.

### Stopping CMaNGOS

To stop CMaNGOS, simply run:

```sh
docker compose down
```

### Updating

To update, pull the latest images:

```sh
docker compose pull
```

Afterwards, re-create the containers:

```sh
docker compose up -d
```

> [!NOTE]
> Selecting specific images via combined revision tag (as described further
> above) will obviously prevent you from updating until you edit each
> respective service in your `compose.yaml` to pull newer images. Attempting to
> update without changing the configured images is not harmful, it will just
> not have any effect.

#### What happens during an update

cmangos-deploy detects upstream CMaNGOS commits that edit already released
migration files. Such changes would otherwise leave your databases in an
inconsistent state and require manual intervention to rectify.

By default, cmangos-deploy will
[automatically re-create your world database][compose-automatic-world-db-corrections]
when a relevant change is detected. Anything in the world database that you may
have changed (your custom NPCs and gameobjects, `npc_vendor` edits, etc.) does
not survive the re-creation, so restore those from a backup if you need them
back (or use
[custom SQL](#modifying-the-world-database-with-custom-changes-optional) to
cleanly preserve the additions/changes).

For the other databases that contain user state, cmangos-deploy cannot safely
re-create them and instead [halts startup][compose-halt-on-edits] until you
intervene; see the next section.

#### When cmangos-deploy asks you to apply changes manually

When a migration edit is detected that affects a database containing user state
(or a world database edit with automatic corrections disabled), cmangos-deploy
halts startup and prints a message naming the affected database(s) and the
GitHub link(s) to the upstream commit(s).

The container stays running while paused; nothing restarts on its own. To
resolve:

1. Open each linked commit on GitHub and read the changes.
2. Apply the equivalent SQL to the running database. From the host:
   ```sh
   docker compose exec database mariadb -u root -p <db>
   ```
   where `<db>` is `characters`, `realmd`, `logs`, or `mangos`. `mariadb` will
   prompt for the password; it matches your `MARIADB_ROOT_PASSWORD` setting in
   `compose.yaml`.
3. When you are done, confirm by running on the host:
   ```sh
   docker compose exec database cmangos-confirm-changes
   ```

cmangos-deploy will then record the acknowledgement and continue startup. If
you instead want to abort, run `docker compose down`.

> [!CAUTION]
> When you run `cmangos-confirm-changes`, cmangos-deploy treats the listed
> commits as applied and continues. It does not check your database to verify
> that the changes you made match what the commits describe. If your manual fix
> is incorrect or incomplete, the database will be in an inconsistent state and
> CMaNGOS may fail to start. The responsibility for matching what the commits
> do is yours; cmangos-deploy provides no further support for resolving these
> issues.

### Creating database backups

It is recommended to perform regular database backups, particularly before
updating.

To automatically create database backups periodically, uncomment the
[`database-backup` service configuration][compose-database-backups] in your
`compose.yaml` and follow the comments for further information.

### Accessing the database

To make certain changes (e.g., managing accounts or changing the realm
configuration) it can be necessary to access the database with a MySQL/MariaDB
client.

A common web-based MySQL/MariaDB database administration tool called
[phpMyAdmin][phpmyadmin] is included and can be enabled by uncommenting the
[`phpmyadmin` service configuration][compose-phpmyadmin] in your
`compose.yaml`. See the comments there for further information.

### Database security

It is not recommended to expose your database to the public (whether through
direct port access, a WAN-accessible phpMyAdmin instance, or any other means).
If you decide to do so, you will have to implement appropriate security
measures. Please note that no further support or guidance regarding this will
be provided here.

> [!CAUTION]
> The default database users with full access to all CMaNGOS data (`root` and
> the user named via the `MARIADB_USER` environment variable) do not have any
> restrictions in place in regards to which IPs/hosts can connect.

## Maintainer

[Michael Serajnik][maintainer]

## Contribute

You are welcome to help out!

[Open an issue][issues] or [make a pull request][pull-requests].

## License

[AGPL-3.0-or-later](LICENSE) © Michael Serajnik

[badge-actions-status]: https://github.com/mserajnik/cmangos-deploy/actions/workflows/build-docker-images.yaml/badge.svg
[badge-actions-status-url]: https://github.com/mserajnik/cmangos-deploy/actions/workflows/build-docker-images.yaml
[badge-latest-build-date]: https://img.shields.io/endpoint?url=https%3A%2F%2Fscripts.mser.at%2Fcmangos-deploy-badges%2Fdate-badge.json
[badge-latest-build-date-url]: https://github.com/mserajnik?tab=packages&repo_name=cmangos-deploy
[badge-latest-classic-build]: https://img.shields.io/endpoint?url=https%3A%2F%2Fscripts.mser.at%2Fcmangos-deploy-badges%2Fclassic-build-badge.json
[badge-latest-classic-build-url]: https://github.com/mserajnik/cmangos-deploy/pkgs/container/cmangos-server-classic
[badge-latest-tbc-build]: https://img.shields.io/endpoint?url=https%3A%2F%2Fscripts.mser.at%2Fcmangos-deploy-badges%2Ftbc-build-badge.json
[badge-latest-tbc-build-url]: https://github.com/mserajnik/cmangos-deploy/pkgs/container/cmangos-server-tbc
[badge-latest-wotlk-build]: https://img.shields.io/endpoint?url=https%3A%2F%2Fscripts.mser.at%2Fcmangos-deploy-badges%2Fwotlk-build-badge.json
[badge-latest-wotlk-build-url]: https://github.com/mserajnik/cmangos-deploy/pkgs/container/cmangos-server-wotlk
[claude-code]: https://www.anthropic.com/product/claude-code
[cmangos]: https://github.com/cmangos
[codex]: https://openai.com/codex
[compose-automatic-world-db-corrections]: https://github.com/mserajnik/cmangos-deploy/blob/master/compose-classic.yaml.example#L34-L46
[compose-custom-sql]: https://github.com/mserajnik/cmangos-deploy/blob/master/compose-classic.yaml.example#L60-L77
[compose-custom-sql-bind-mount]: https://github.com/mserajnik/cmangos-deploy/blob/master/compose-classic.yaml.example#L17
[compose-database-backups]: https://github.com/mserajnik/cmangos-deploy/blob/master/compose-classic.yaml.example#L167-L203
[compose-halt-on-edits]: https://github.com/mserajnik/cmangos-deploy/blob/master/compose-classic.yaml.example#L47-L59
[compose-phpmyadmin]: https://github.com/mserajnik/cmangos-deploy/blob/master/compose-classic.yaml.example#L205-L225
[docker]: https://docs.docker.com/get-docker/
[docker-compose]: https://docs.docker.com/compose/install/
[image-cmangos-packages]: https://github.com/mserajnik?tab=packages&repo_name=cmangos-deploy
[issues]: https://github.com/mserajnik/cmangos-deploy/issues
[maintainer]: https://github.com/mserajnik
[mangosd-gm-options]: https://github.com/mserajnik/cmangos-deploy/blob/master/config/classic/mangosd.conf.example#L1180-L1295
[phpmyadmin]: https://www.phpmyadmin.net/
[playerbots]: https://github.com/cmangos/playerbots
[pull-requests]: https://github.com/mserajnik/cmangos-deploy/pulls
[vmangos-deploy]: https://github.com/mserajnik/vmangos-deploy
