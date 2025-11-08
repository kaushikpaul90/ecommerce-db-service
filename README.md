# DATABASE_SERVICE

A PostgreSQL-backed microservice providing RESTful CRUD APIs for e-commerce operations including orders, inventory, payments, and shipments.

## Features

- CRUD operations for:
  - Orders (with refund support)
  - Inventory 
  - Inventory Reservations (with stock locking)
  - Payments
  - Shipments
- FastAPI-based REST API
- PostgreSQL database with SQLAlchemy
- Kubernetes-ready with Helm deployment
- Horizontal Pod Autoscaling (HPA) support
- GitHub Actions CI/CD pipeline

## Prerequisites

- Python 3.11+
- PostgreSQL
- Docker (optional)
- Kubernetes & Helm (optional)

## Configuration

Set the following environment variables (or create `.env` file):

```bash
DB_HOST=localhost      # PostgreSQL host
DB_PORT=5432          # PostgreSQL port
DB_NAME=ecommerce_db  # Database name
DB_USER=postgres      # Database user
DB_PASSWORD=postgres  # Database password
```

## Local Development

1. Create a Python virtual environment:
   ```bash
   python -m venv .venv
   source .venv/bin/activate
   pip install -r requirements.txt
   ```

2. Initialize PostgreSQL database:
   ```bash
   cd sql
   ./init_db.sh
   ```

3. Start the service:
   ```bash
   uvicorn app:app --reload --host 0.0.0.0 --port 8000
   ```

4. Access OpenAPI documentation at: http://localhost:8000/docs

## API Endpoints

### Health Check
- `GET /health` - Service health check

### Orders
- `POST /orders` - Create order
- `GET /orders` - List orders
- `GET /orders/{id}` - Get order
- `PUT /orders/{id}` - Update order
- `DELETE /orders/{id}` - Delete order
- `POST /orders/{id}/refund-metadata` - Update refund status

### Inventory
- `POST /inventory` - Create/update inventory
- `GET /inventory` - List inventory
- `GET /inventory/{sku}` - Get inventory
- `PUT /inventory/{sku}` - Update inventory
- `DELETE /inventory/{sku}` - Delete inventory

### Inventory Reservations
- `POST /inventory/reserve` - Create reservation
- `GET /inventory/reserve` - List reservations
- `GET /inventory/reserve/{id}` - Get reservation
- `PUT /inventory/reserve/{id}` - Update reservation
- `DELETE /inventory/reserve/{id}` - Delete reservation

### Payments & Shipments
- CRUD endpoints following similar patterns
- See OpenAPI docs for details

## Docker Deployment

Build and run:
```bash
docker build -t <registry>/<repo>/database-service:latest .
docker run -p 8000:8000 \
  -e DB_HOST=host.docker.internal \
  -e DB_PORT=5432 \
  -e DB_NAME=ecommerce_db \
  -e DB_USER=postgres \
  -e DB_PASSWORD=postgres \
  <registry>/<repo>/database-service:latest
```

## Kubernetes / Helm Deployment

1. Create PostgreSQL secrets:
   ```bash
   cd infra/postgres
   ./create-secret.sh default .env
   ```

2. Deploy PostgreSQL (if needed):
   ```bash
   kubectl apply -f infra/postgres/k8s-postgres.yaml
   ```

3. Deploy service with Helm:
   ```bash
   ./deploy.sh
   ```

The service supports HPA with:
- Min replicas: 1
- Max replicas: 10
- Target CPU utilization: 70%

## CI/CD

The GitHub Actions workflow (.github/workflows/ci-build.yaml) handles:
- Building Docker image
- Multi-arch support (amd64/arm64)
- Pushing to Docker Hub
- Requires secrets:
  - `DOCKER_HUB_USERNAME`
  - `DOCKER_HUB_PASSWORD`

## Notes

- Uses SQLAlchemy Core for simplicity
- Transaction support for inventory operations
- Row-level locking for inventory updates
- Production deployment should:
  - Use database migrations (Alembic)
  - Configure proper resource limits
  - Use secure secret management
  - Set up monitoring and logging