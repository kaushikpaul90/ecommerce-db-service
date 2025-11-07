# DATABASE_SERVICE

This microservice provides RESTful CRUD APIs backed by PostgreSQL.
It mirrors the structure and conventions of the existing Order microservice.

## Quickstart (local)

1. Create a Python virtualenv and install dependencies:
   ```bash
   python -m venv .venv
   source .venv/bin/activate
   pip install -r requirements.txt
   ```

2. Create a local PostgreSQL database and update `.env` with connection information.

3. Start the service:
   ```bash
   uvicorn app:app --reload --host 0.0.0.0 --port 8000
   ```

4. API endpoints:
   - `GET /health` - health check
   - `POST /items` - create item
   - `GET /items` - list items
   - `GET /items/{id}` - get item
   - `PUT /items/{id}` - update item
   - `DELETE /items/{id}` - delete item

## Docker

Build and run:
```bash
docker build -t <your-registry>/<your-repo>/database-service:latest .
docker run -e DB_HOST=... -e DB_USER=... -e DB_PASSWORD=... -p 8000:8000 <your-registry>/<your-repo>/database-service:latest
```

## Kubernetes / Helm

Deploy with Helm:
```bash
./deploy.sh
```

The `helm_chart/` directory contains the chart and values files. Image secrets and DB credentials should be stored as CI/CD secrets in your GitHub Actions and Kubernetes secrets.

## CI/CD

The included GitHub Actions pipeline builds and pushes the Docker image to the registry using secrets (see `.github/workflows/ci-build.yaml`).

## Notes

- This project uses SQLAlchemy Core for simplicity. For production, use migrations (Alembic) and proper secrets management.
- Image tag `latest` is used by default to mirror the Order microservice preferences.
