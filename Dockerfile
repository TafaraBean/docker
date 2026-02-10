FROM n8nio/runners:latest
USER root

# Example: add extra JS deps (optional)
RUN cd /opt/runners/task-runner-javascript && pnpm add moment uuid

# Example: add extra Python deps
RUN cd /opt/runners/task-runner-python && uv pip install numpy pandas



USER runner