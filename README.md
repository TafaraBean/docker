# n8n with external task runners (Docker Compose)

A Docker Compose stack for self-hosting [n8n](https://n8n.io), the workflow automation tool, with its task runners in a separate container. n8n calls this "external" mode. JavaScript and Python code from Code nodes runs in the `n8n-runner` container instead of inside the main n8n process.

## What the stack runs

| Service | Image | Container | Role |
|---|---|---|---|
| `n8n` | `n8nio/n8n:2.6.3` | `n8n_main` | n8n editor, API and workflow engine. Also hosts the task broker that the runner connects to. |
| `n8n-runner` | `n8nio/runners:2.6.3` | `n8n_runner` | Task runner launcher that executes Code-node JavaScript and Python. It connects to the broker at `http://n8n_main:5679`. |

Both services use `restart: unless-stopped`, and the runner starts after n8n (`depends_on`).

**Ports**

| Host | Container | Used for |
|---|---|---|
| 5678 | 5678 | n8n web UI and API |
| 5679 | 5679 | Task broker (runner to n8n) |

**Volume.** The named volume `n8n_data` is mounted at `/home/node/.n8n` in the `n8n` container. It holds n8n's local data, including workflows, credentials and the key used to encrypt credentials.

**Main settings in `docker-compose.yml`**

- `n8n`
  - `N8N_RUNNERS_MODE=external`: run code in the separate runner container.
  - `N8N_RUNNERS_BROKER_LISTEN_ADDRESS=0.0.0.0` and `N8N_RUNNERS_BROKER_PORT=5679`: let the runner container reach the broker.
  - `N8N_LISTEN_ADDRESS=0.0.0.0`: the address the n8n server listens on inside its container.
- `n8n-runner`
  - `N8N_RUNNERS_TASK_BROKER_URI`: where to find the broker.
  - `N8N_RUNNERS_STDLIB_ALLOW` and `N8N_RUNNERS_EXTERNAL_ALLOW`: which Python modules Code nodes may import. They are set to all standard-library modules plus `yfinance`. See the notes below.
- Both services: `N8N_RUNNERS_AUTH_TOKEN` is the shared secret the runner uses to authenticate with the broker. The value must be the same in both services.

## Project structure

```
.
├── docker-compose.yml     # The n8n + task runner stack
├── Dockerfile             # Optional custom runner image with extra JS (moment, uuid) and Python (numpy, pandas) packages
└── n8n-task-runners.json  # Runner launcher overrides: module allowlists for the JS and Python runners
```

`docker-compose.yml` as written does not use `Dockerfile` or `n8n-task-runners.json`. To use them, see [Custom runner image](#custom-runner-image-optional) below.

## Getting started

You need Docker with the Compose plugin (`docker compose`).

### 1. Set your own runner auth token

The `N8N_RUNNERS_AUTH_TOKEN` value committed in `docker-compose.yml` is a placeholder. **Before using this stack for anything other than local testing, change it to your own long random secret.** Change it in both services so the values still match. One way to generate a secret:

```bash
openssl rand -hex 32
```

It is better not to keep the secret in the compose file at all:

1. Put `N8N_RUNNERS_AUTH_TOKEN=<your secret>` in a `.env` file next to `docker-compose.yml`. Don't commit the `.env` file.
2. In both services, change the line to `N8N_RUNNERS_AUTH_TOKEN=${N8N_RUNNERS_AUTH_TOKEN}`.

### 2. Start the stack

```bash
docker compose up -d
docker compose ps
```

### 3. Open n8n

Go to <http://localhost:5678>. The first time, n8n asks you to create an owner account.

### Logs and stopping

```bash
docker compose logs -f n8n           # or: docker compose logs -f n8n-runner
docker compose down                  # stop and remove the containers; the n8n_data volume is kept
docker compose down -v               # also delete the n8n_data volume (all workflows and credentials)
```

### Upgrading

n8n expects the runners image to be the same version as n8n. Change both image tags to the same new version, then run:

```bash
docker compose pull
docker compose up -d
```

## Custom runner image (optional)

`Dockerfile` builds on `n8nio/runners`. It installs `moment` and `uuid` for the JavaScript runner and `numpy` and `pandas` for the Python runner. To use it:

1. Change `FROM n8nio/runners:latest` to the n8n version, e.g. `n8nio/runners:2.6.3`.
2. To apply `n8n-task-runners.json`, add `COPY n8n-task-runners.json /etc/n8n-task-runners.json` before `USER runner`. This is the location n8n's docs give for the launcher config. Complete the file first (see notes).
3. In `docker-compose.yml`, replace the `image:` line of `n8n-runner` with `build: .`.
4. Run `docker compose up -d --build`.

Code nodes can only import an installed package if it is also on the allowlist. Python packages go in `N8N_RUNNERS_EXTERNAL_ALLOW` and JavaScript packages go in `NODE_FUNCTION_ALLOW_EXTERNAL`.

## Notes

- **`n8n-task-runners.json` is incomplete.** It only has `env-overrides`. The stock launcher config inside the `n8nio/runners` image also defines each runner's `command`, `args`, `workdir`, `health-check-server-port` and `allowed-env`. Your file replaces the stock one, so copy these overrides into a copy of the stock file instead of using this file on its own.
- **`yfinance` is allowlisted but never installed.** `N8N_RUNNERS_EXTERNAL_ALLOW` includes `yfinance`, but nothing installs it. The Dockerfile only adds `numpy` and `pandas`.
- **The allowlist environment variables may have no effect.** n8n's docs say to set the allowlists in the launcher config's `env-overrides`. The stock config does not pass `N8N_RUNNERS_STDLIB_ALLOW` or `N8N_RUNNERS_EXTERNAL_ALLOW` through from the container environment, so the values set in `docker-compose.yml` may be ignored. If Python imports are blocked, set the allowlists in the launcher config instead.
- **`moment` and `uuid` are blocked.** `n8n-task-runners.json` sets `NODE_FUNCTION_ALLOW_EXTERNAL` to an empty value. Code nodes can't import these packages from the Dockerfile until you add them to that list.
- **Port 5679 doesn't need to be published.** The runner reaches the broker over the Compose network, so the host mapping for 5679 isn't needed. Removing it keeps the broker off your host's network.
- **`version: "3.8"` is obsolete.** Current Docker Compose ignores the `version:` key and prints a warning. The warning is harmless.
- **HTTP only.** n8n is served over plain HTTP on `localhost`. The stack is set up for local use, not for exposing to a network.
