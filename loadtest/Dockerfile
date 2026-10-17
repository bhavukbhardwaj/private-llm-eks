# Small in-cluster load test client (arm64 build, runs on a system node). Standard library only.
FROM python:3.13-slim
WORKDIR /app
COPY loadtest.py .
ENTRYPOINT ["python", "/app/loadtest.py"]
