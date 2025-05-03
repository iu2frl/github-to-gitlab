# GitHub to GitLab Mirror Bot (via Docker)

This project periodically mirrors all GitHub repositories you have access to, pushing them to GitLab. It automatically creates any missing GitLab repositories and mirrors all branches, tags, and commits.

## Features

- Fetches list of all GitHub repositories (public and private)
- Automatically creates missing GitLab repositories
- Performs full `git push --mirror` to GitLab
- Runs on a schedule using cron (default: every hour)
- Fully containerized via Docker

---

## Requirements

- Docker + Docker Compose
- GitHub token with access to your repositories (`repo` scope)
- GitLab token with permissions to create and push repositories (`api` scope)

---

## Environment Variables

Set these environment variables in `docker-compose.yml`:

| Variable           | Description                                   |
|--------------------|-----------------------------------------------|
| `GITHUB_TOKEN`     | Personal GitHub token                         |
| `GITLAB_TOKEN`     | Personal GitLab token                         |
| `GITLAB_NAMESPACE` | GitLab username or group where to mirror repos |

---

## Usage

1. Clone this repository:

```bash
git clone https://github.com/your-username/github-gitlab-mirror.git
cd github-gitlab-mirror
```

2. Edit `docker-compose.yml` and set your tokens and GitLab namespace.

3. Build and start the container:

```bash
docker compose up -d --build
```

4. Check logs:

```bash
docker compose logs -f
```

---

## Adjusting Sync Frequency

Edit `crontab.txt` to change how often the mirror runs.

Default (every hour):
```cron
0 * * * * /mirror.sh >> /var/log/mirror.log 2>&1
```

Example: every 15 minutes:
```cron
*/15 * * * * /mirror.sh >> /var/log/mirror.log 2>&1
```

---

## Data Volume

Temporary cloned repositories are stored in `./mirror-data`. This volume is not persistent across container restarts.

---

## Security

- Tokens are passed as environment variables.
- **Do not commit or expose your tokens publicly.**

---

## License

MIT – Free to use and modify.