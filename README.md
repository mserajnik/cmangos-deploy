<h1>
  <img src=".github/logo.webp" alt="" height="100">
  <br>
  cmangos-deploy
</h1>

[![Lint status][badge-lint-status]][badge-lint-status-url]
[![Build status][badge-build-status]][badge-build-status-url]  
[![Latest Classic build][badge-latest-classic-build]][badge-latest-classic-build-url]  
[![Latest TBC build][badge-latest-tbc-build]][badge-latest-tbc-build-url]  
[![Latest WotLK build][badge-latest-wotlk-build]][badge-latest-wotlk-build-url]  
[![Latest build date][badge-latest-build-date]][badge-latest-build-date-url]

> A Docker setup for CMaNGOS

---

> [!WARNING]
> cmangos-deploy was relaunched on 2026-10-04 with major changes that require
> adjusting your configuration. If you used it before this date, work through
> the [breaking changes](docs/breaking-changes.md) before you update.

---

> [!TIP]
> Also check out my similar Docker setups:
>
> - [vmangos-deploy][vmangos-deploy] for [VMaNGOS][vmangos], a progressive
>   Vanilla server emulator that aims to eventually support all versions from
>   `1.2.4.4222` to `1.12.1.5875`.
> - [tortoise-deploy][tortoise-deploy] for [Tortoise-WoW][tortoise-wow], a
>   community-driven restoration of Turtle WoW's `1.18.1.7272` patch with
>   additions for solo play.

cmangos-deploy is a Docker-based solution for running [CMaNGOS][cmangos]. It
offers:

- __Prebuilt Docker images for both `amd64` and `arm64`, built with GitHub
  Actions__: simply pull the images for your architecture and get started.
- __The ability to run CMaNGOS configured for any of its supported
  expansions__: prebuilt images for all three expansions, Classic, TBC, and
  WotLK, are provided, each with built-in [Playerbot][playerbots] support.
- __Automated database migrations__: when you pull the latest Docker images and
  re-create the containers, the migrations are applied automatically to keep
  your databases up to date at all times.

> [!NOTE]
> The Docker images are built daily when CMaNGOS or Playerbot has had new
> commits since the last build. Additionally, every Monday, the latest images
> are rebuilt to keep their system packages up to date, even if neither CMaNGOS
> nor Playerbot has changed.

## Quick start

The steps below get a local installation running quickly, for playing on the
same machine. You need [Docker][docker] with [Docker Compose][docker-compose].
The steps set up Classic. For TBC or WotLK, replace `classic` with `tbc` or
`wotlk` in the steps below.

1. Clone the repository and copy the example configuration files:

   ```sh
   git clone https://github.com/mserajnik/cmangos-deploy.git
   cd cmangos-deploy
   cp config/classic/mangosd.conf.example config/classic/mangosd.conf
   cp config/classic/realmd.conf.example config/classic/realmd.conf
   cp config/classic/ahbot.conf.example config/classic/ahbot.conf
   cp config/classic/aiplayerbot.conf.example config/classic/aiplayerbot.conf
   cp config/classic/anticheat.conf.example config/classic/anticheat.conf
   cp config/classic/mods.conf.example config/classic/mods.conf
   ```

   Only Classic has `mods.conf.example`, so skip the last line for TBC and
   WotLK. Then adjust the copies to your liking, for example the `GameType` or
   the `RealmZone` in your `config/classic/mangosd.conf`. The files describe
   their options. Some options are set by the image and cannot be configured in
   the files. A comment at the top of your `mangosd.conf`, `realmd.conf`, and
   `anticheat.conf` lists them.

2. Copy the example Compose file:

   ```sh
   cp compose-classic.yaml.example compose.yaml
   ```

3. Adjust your `compose.yaml`: set `TZ` to your time zone in every service, and
   change the database passwords. On Linux, set `CMANGOS_UID` and `CMANGOS_GID`
   to your user's UID and GID. The [Docker Compose reference](docs/compose.md)
   explains every setting.

4. Copy the contents of your client directory into
   `storage/classic/mangosd/client-data/`, and extract the client data:

   ```sh
   docker compose run --rm extract-client-data
   ```

   Use the client version that CMaNGOS supports for your chosen expansion, as
   the [expansions section](docs/usage.md#expansions) lists. Extracting can
   take many hours, and the
   [extracting the client data section](docs/usage.md#extracting-the-client-data)
   describes the details.

5. Start CMaNGOS and follow its output:

   ```sh
   docker compose up -d
   docker compose logs -f mangosd
   ```

   The first start takes longer, because it creates the databases. Do not
   interrupt it, or you may have to remove the database volume and start over.
   The server is ready when it prints `CMANGOS: World initialized`.

6. Create your first account. To do that, attach to the server console:

   ```sh
   docker compose attach mangosd
   ```

   Then create the account:

   ```text
   account create <account-name> <password>
   ```

   If you want to give the account Game Master permissions, for example, the
   [accounts section](docs/usage.md#accounts) explains the account levels,
   along with the expansion level that an account needs to access the content
   of TBC or WotLK, if you set up either of them. To leave the console again,
   press <kbd>Ctrl</kbd>+<kbd>P</kbd> and then
   <kbd>Ctrl</kbd>+<kbd>Q</kbd>.

7. Adjust the `realmlist.wtf` in the client directory, or in `Data/<locale>/`
   for WotLK, to point the client at the local server:

   ```text
   set realmlist 127.0.0.1
   ```

   Then start the client and log in with the account you created.

For the full instructions, see the [usage documentation](docs/usage.md).

### Using a coding agent

A coding agent such as [Claude Code][claude-code] or [Codex][codex] can walk
you through the setup. Try a prompt like this one:

```text
Help me install and set up https://github.com/mserajnik/cmangos-deploy.
First, clone the repository and read the README and every file under docs/
carefully.
Then guide me through the installation process step by step, following the
documentation closely.
Do as much of the setup yourself as you safely can so that I only have to step
in when a manual action or personal preference is required.
Ask me about my preferences whenever a choice has to be made, explain the
relevant options clearly, and tailor your instructions to the OS I am using.
Assume that I am not familiar with CMaNGOS or Docker and that I have not read
the documentation myself.
For steps that I need to perform manually, give me clear instructions and exact
commands where appropriate.
Do not assume user-facing choices such as the expansion, optional services, or
networking-related preferences.
Ask me whenever the documentation presents a meaningful choice.
For settings and options that the documentation or the CMaNGOS example
configuration files indicate should generally be left alone, keep the defaults
unless I explicitly ask for something else.
Do not change settings and options that the documentation or the CMaNGOS
example configuration files indicate should not be changed.
```

The prompt that works best depends on the agent and the model.

> [!CAUTION]
> You use coding agents at your own risk, and you are responsible for the
> access you give them. The maintainer of this project is not liable for any
> damage or data loss they cause. Take precautions such as sandboxed access and
> limited permissions, and do not run them with `--yolo` or similar options
> that bypass their safety checks.

## Documentation

- [Usage](docs/usage.md): choosing images, the client data, running and
  updating CMaNGOS, Playerbot and AHBot, backups, and database access.
- [Docker Compose reference](docs/compose.md): every setting in the Compose
  files.
- [Breaking changes](docs/breaking-changes.md): the changes you have to act on
  when you update.

## Modifications

The images contain [CMaNGOS][cmangos] with the patches from
[`docker/patches/`](docker/patches). Patches in `all/` apply to every
expansion, and patches in `classic/`, `tbc/`, or `wotlk/` to that expansion
only. A patch exists for one of these reasons:

- It corrects a problem that breaks the build or the running server.
- It adapts the code to how the images are built and run.
- It changes an upstream default to a value that gives objectively better
  results.

Every patch adds a comment to the code it changes, which explains what the
change does and why. A patch is removed once it is no longer needed, so the
directory can be empty at times.

## Maintainer

[Michael Serajnik][maintainer]

## Contribute

You are welcome to help out!

[Open an issue][issues] or [make a pull request][pull-requests].

## Licenses

- [`AGPL-3.0-or-later`][license-agpl-3.0-or-later] (Code)
- [`GPL-2.0-only`][license-gpl-2.0-only] (Database entrypoint script, based on
  MariaDB's)
- [`GPL-2.0-or-later`][license-gpl-2.0-or-later] (Some patches, matching
  CMaNGOS source)
- [`FSFULLRWD`][license-fsfullrwd] (Some patches, matching CMaNGOS source)
- [`CC-BY-SA-4.0`][license-cc-by-sa-4.0] (Documentation, graphic assets, and
  issue templates)
- [`CC0-1.0`][license-cc0-1.0] (Configuration files)

This project follows the [REUSE specification][reuse-spec].

## Disclaimer

cmangos-deploy is an independent, community-made Docker setup for the
open-source [CMaNGOS][cmangos] project. It is not affiliated with, endorsed by,
or sponsored by Blizzard Entertainment, Inc., and it is not an official CMaNGOS
project.

This project includes no game client data or other copyrighted game assets. You
must supply your own legitimate game client, from which the required data is
extracted locally on your own machine. It is intended for private,
non-commercial use only and comes with no warranty.

[badge-build-status]: https://github.com/mserajnik/cmangos-deploy/actions/workflows/build-docker-images.yaml/badge.svg
[badge-build-status-url]: https://github.com/mserajnik/cmangos-deploy/actions/workflows/build-docker-images.yaml
[badge-latest-build-date]: https://img.shields.io/endpoint?url=https%3A%2F%2Fscripts.mser.at%2Fcmangos-deploy-badges%2Fdate-badge.json
[badge-latest-build-date-url]: https://github.com/mserajnik?tab=packages&repo_name=cmangos-deploy
[badge-latest-classic-build]: https://img.shields.io/endpoint?url=https%3A%2F%2Fscripts.mser.at%2Fcmangos-deploy-badges%2Fclassic-build-badge.json
[badge-latest-classic-build-url]: https://github.com/mserajnik/cmangos-deploy/pkgs/container/cmangos-server-classic
[badge-latest-tbc-build]: https://img.shields.io/endpoint?url=https%3A%2F%2Fscripts.mser.at%2Fcmangos-deploy-badges%2Ftbc-build-badge.json
[badge-latest-tbc-build-url]: https://github.com/mserajnik/cmangos-deploy/pkgs/container/cmangos-server-tbc
[badge-latest-wotlk-build]: https://img.shields.io/endpoint?url=https%3A%2F%2Fscripts.mser.at%2Fcmangos-deploy-badges%2Fwotlk-build-badge.json
[badge-latest-wotlk-build-url]: https://github.com/mserajnik/cmangos-deploy/pkgs/container/cmangos-server-wotlk
[badge-lint-status]: https://github.com/mserajnik/cmangos-deploy/actions/workflows/lint.yaml/badge.svg
[badge-lint-status-url]: https://github.com/mserajnik/cmangos-deploy/actions/workflows/lint.yaml
[claude-code]: https://www.anthropic.com/product/claude-code
[cmangos]: https://github.com/cmangos
[codex]: https://openai.com/codex
[docker]: https://docs.docker.com/get-docker/
[docker-compose]: https://docs.docker.com/compose/install/
[issues]: https://github.com/mserajnik/cmangos-deploy/issues
[license-agpl-3.0-or-later]: LICENSES/AGPL-3.0-or-later.txt
[license-cc-by-sa-4.0]: LICENSES/CC-BY-SA-4.0.txt
[license-cc0-1.0]: LICENSES/CC0-1.0.txt
[license-fsfullrwd]: LICENSES/FSFULLRWD.txt
[license-gpl-2.0-only]: LICENSES/GPL-2.0-only.txt
[license-gpl-2.0-or-later]: LICENSES/GPL-2.0-or-later.txt
[maintainer]: https://github.com/mserajnik
[playerbots]: https://github.com/cmangos/playerbots
[pull-requests]: https://github.com/mserajnik/cmangos-deploy/pulls
[reuse-spec]: https://reuse.software/spec/
[tortoise-deploy]: https://github.com/mserajnik/tortoise-deploy
[tortoise-wow]: https://github.com/tortoise-wow/tortoise-wow
[vmangos]: https://github.com/vmangos/core
[vmangos-deploy]: https://github.com/mserajnik/vmangos-deploy
