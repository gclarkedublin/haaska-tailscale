# --------------------------
# Stage 1: Python dependencies
# --------------------------
ARG TAILSCALE_VERSION=1.78.1
ARG PYTHON_VERSION=3.13
FROM python:${PYTHON_VERSION}-bookworm AS builder

WORKDIR /app
COPY ./haaska/haaska.py .
COPY ./haaska/requirements.txt .
COPY ./config.json ./config.json

RUN pip install -t . -r requirements.txt

# --------------------------
# Stage 2: Tailscale binaries (ARM64)
# --------------------------
FROM alpine:latest AS tailscale
ARG TAILSCALE_VERSION
WORKDIR /app

RUN wget https://pkgs.tailscale.com/stable/tailscale_${TAILSCALE_VERSION}_arm64.tgz && \
    tar xzf tailscale_${TAILSCALE_VERSION}_arm64.tgz --strip-components=1

# --------------------------
# Stage 3: Final Lambda image (ARM64)
# --------------------------
FROM public.ecr.aws/lambda/python:${PYTHON_VERSION}-arm64 AS final

# Set environment variables
ENV PYTHON_VERSION=${PYTHON_VERSION}
ENV PROXY_URL=socks5h://localhost:1055

# Add AWS Lambda Runtime Interface Emulator for local testing
ADD https://github.com/aws/aws-lambda-runtime-interface-emulator/releases/latest/download/aws-lambda-rie /usr/local/bin/aws-lambda-rie
RUN chmod +x /usr/local/bin/aws-lambda-rie

# Copy custom entrypoint and make executable
COPY ./custom_entrypoint /var/runtime/custom_entrypoint
RUN chmod +x /var/runtime/custom_entrypoint

# Copy Python dependencies from builder
COPY --from=builder /app/ /var/task

# Copy Tailscale binaries
COPY --from=tailscale /app/tailscaled /var/runtime/tailscaled
COPY --from=tailscale /app/tailscale /var/runtime/tailscale

# Create necessary symlinks for Tailscale
RUN mkdir -p /var/run /var/cache /var/lib /var/task && \
    ln -s /tmp/tailscale /var/run/tailscale && \
    ln -s /tmp/tailscale /var/cache/tailscale && \
    ln -s /tmp/tailscale /var/lib/tailscale && \
    ln -s /tmp/tailscale /var/task/tailscale

# Expose port for local testing
EXPOSE 8080

# Lambda entrypoint
ENTRYPOINT ["/var/runtime/custom_entrypoint"]
CMD ["haaska.event_handler"]
