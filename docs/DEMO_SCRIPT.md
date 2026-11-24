# Boss Demonstration Script (5–7 minutes)

## 1. Explain the architecture (1 minute)

"This is a standalone two-service application. Nginx is the only public entry point. It serves the dashboard and forwards API requests to a Node.js service over a private Docker network."

## 2. Show the application (1 minute)

Open `http://localhost:8080`, run the health check, and inspect the runtime information.

## 3. Show operations (2 minutes)

Run:

```bash
docker compose ps
docker compose logs --tail=30
docker stats
```

Explain the difference between container status, application health, and resource usage.

## 4. Demonstrate an incident (2 minutes)

```bash
docker compose stop api
```

Click "Run health check". Explain that the API upstream is unavailable while the Nginx dashboard remains reachable.

Recover:

```bash
docker compose start api
```

Run the health check again and show recovery.

## 5. Explain automation (1 minute)

Open `.github/workflows/ci.yml`. Explain that every push or pull request to `main` runs tests and builds both images. This lab does not automatically deploy to a public server.
