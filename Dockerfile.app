FROM ghcr.io/selkies-project/selkies-vdi/app-streaming:master-focal

RUN apt-get update && \
    apt-get install -y \
        firefox && \
    rm -rf /var/lib/apt/lists/*

ENV ENABLE_WM=false
ENV EXEC_CMD=firefox