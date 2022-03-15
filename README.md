# Xpra for Selkies

Container for running Xpra and HTML5 client on Selkies in sidecar architecture.

Xpra improvements:
- Progressive Web App (PWA) support.
- Pass HTML5 config settings via env vars.
- Nginx proxy in front of Xpra server and Xpra-HTML5.
- Configure Xpra for endpoint isolation.

## Local Development

Develop locally with Docker and docker compose.

- nginx proxy that is normally part of the xpra container is overridden with dev config that handles the app path prefix suitable for localhost development.
- xpra-html5 contents are mounted to the dev container, so refreshing the page loads changes.
- NOTE: only some of the xpra-html5/html5 contents are mounted as the www root is modified by the xpra entrypoint script for PWA support.

1. Build the images:

```
docker-compose build
```

2. Start the `desktop`, and `xpra` containers:

```
docker-compose up
```

3. Connect to the dev container on port 8080:

```
echo "Connect to: http://localhost:8080"
```