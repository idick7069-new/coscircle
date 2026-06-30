# Zeabur deployment

CosCircle is deployed as three Zeabur services in one project:

- `mysql`: Zeabur MySQL prebuilt service
- `api`: Express backend, built from `Dockerfile.api`
- `web`: Flutter web app, built from `Dockerfile.web`

The service names `api` and `web` are intentional. Zeabur can auto-match
`Dockerfile.api` and `Dockerfile.web` by service name.

## 1. Create services

1. Create a Zeabur project.
2. Add a MySQL service.
3. Add a Git service from this repository named `api`.
4. Add another Git service from this repository named `web`.

If Zeabur does not auto-pick the Dockerfile, set the service variable:

```env
ZBPACK_DOCKERFILE_NAME=api
```

or:

```env
ZBPACK_DOCKERFILE_NAME=web
```

## 2. Initialize MySQL

Run `backend/db/schema.sql` in the MySQL service command console or with a MySQL
client connected to the Zeabur database.

Optional initial event seed:

```bash
node backend/scripts/scrape-events.js --import
```

Run the scraper from the `api` service after the MySQL variables are configured.

## 3. API environment variables

Set these on the `api` service:

```env
NODE_ENV=production
PORT=8080
MYSQL_HOST=<mysql host from Zeabur>
MYSQL_PORT=3306
MYSQL_USER=<mysql user from Zeabur>
MYSQL_PASSWORD=<mysql password from Zeabur>
MYSQL_DATABASE=<mysql database from Zeabur>
EVENT_SCRAPER_ENABLED=true
EVENT_SCRAPER_TIME_ZONE=Asia/Taipei
CORS_ORIGINS=https://<web-domain>
```

Generate a Zeabur domain for the `api` service, then verify:

```text
https://<api-domain>/api/health
```

## 4. Web environment variables

Set this on the `web` service before building:

```env
API_BASE_URL=https://<api-domain>/api
```

The Flutter release build requires HTTPS for `API_BASE_URL`.

Generate a Zeabur domain for the `web` service. After that, update the `api`
service `CORS_ORIGINS` to the final web origin and redeploy the API service.

## 5. Suggested deploy order

1. Deploy `mysql`.
2. Import `backend/db/schema.sql`.
3. Deploy `api`.
4. Generate the API domain and verify `/api/health`.
5. Deploy `web` with `API_BASE_URL=https://<api-domain>/api`.
6. Generate the web domain.
7. Set `api` `CORS_ORIGINS=https://<web-domain>` and redeploy `api`.

