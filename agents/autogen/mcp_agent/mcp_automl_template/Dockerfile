# MCP AutoML Server - OpenShift-ready image (uv)
# Build from mcp_agent: docker build -f mcp_automl_template/Dockerfile -t <image> mcp_automl_template/

FROM python:3.12-slim

WORKDIR /app

# Non-privileged user for OpenShift (UID 1001)
RUN groupadd -r appuser && useradd -r -u 1001 -g appuser appuser

# Install uv for fast dependency management
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# Copy project files for dependency installation
COPY pyproject.toml .
COPY mcp_server.py register_tools.py utils.py ./

# Install the project and its dependencies using uv
RUN uv pip install --system --no-cache .

# Copy config and data files (not needed for install)
COPY tools_config.yaml churn_schema.json ./

# Change ownership to non-privileged user
RUN chown -R appuser:appuser /app

USER appuser

EXPOSE 8080
ENV PORT=8080

CMD ["python", "mcp_server.py"]
