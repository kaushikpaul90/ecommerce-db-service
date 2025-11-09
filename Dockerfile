############################################################
# Dockerfile for Order Service (FastAPI microservice)
# Builds a minimal Python 3.11 container for production use
############################################################

# Use official Python slim image for smaller footprint
FROM python:3.11-slim

# Prevent Python from writing .pyc files and enable stdout/stderr buffering
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV POETRY_VIRTUALENVS_CREATE=false

# Set working directory inside the container
WORKDIR /app

# Install system dependencies required to build some Python packages (e.g. psycopg2)
# Keep apt lists ephemeral to minimize image size.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential \
    gcc \
    libpq-dev \
    ca-certificates \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user
RUN useradd --create-home --shell /bin/bash appuser
ENV HOME=/home/appuser

# Install Python dependencies first (leverage Docker cache)
COPY requirements.txt /app/requirements.txt
RUN pip install --upgrade pip && \
    pip install --no-cache-dir -r /app/requirements.txt

# Copy application code
COPY . /app
RUN chown -R appuser:appuser /app

USER appuser

# Expose FastAPI service port
EXPOSE 8000

# Run the FastAPI app defined in [app.py](app.py) (FastAPI instance `app`)
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers"]