ARG TS_VERSION=1.78.1
ARG PYTHON_VERSION=3.13
FROM python:${PYTHON_VERSION}-bookworm as builder
WORKDIR /app
COPY ./haaska/haaska.py .
COPY ./haaska/requirements.txt .
COPY ./config.json ./config.json
RUN pip install -t . -r requirements.txt

FROM alpine:latest as tailscale
ARG TS_VERSION
WORKDIR /app
COPY . ./
RUN wget https://pkgs.tailscale.com/stable/tailscale_${TS_VERSION}_amd64.tgz && \
  tar xzf tailscale_${TS_VERSION}_amd64.tgz --strip-components=1
COPY . ./


FROM public.ecr.aws/lambda/python:${PYTHON_VERSION} as final
ARG PYTHON_VERSION
ENV PYTHON_VERSION=${PYTHON_VERSION}

#can't test locally without it
ADD https://github.com/aws/aws-lambda-runtime-interface-emulator/releases/latest/download/aws-lambda-rie /usr/local/bin/aws-lambda-rie
RUN chmod 755 /usr/local/bin/aws-lambda-rie
COPY ./custom_entrypoint /var/runtime/custom_entrypoint
COPY --from=builder /app/ /var/task
COPY --from=tailscale /app/tailscaled /var/runtime/tailscaled
COPY --from=tailscale /app/tailscale /var/runtime/tailscale
RUN mkdir -p /var/run && ln -s /tmp/tailscale /var/run/tailscale && \
    mkdir -p /var/cache && ln -s /tmp/tailscale /var/cache/tailscale && \
    mkdir -p /var/lib && ln -s /tmp/tailscale /var/lib/tailscale && \
    mkdir -p /var/task && ln -s /tmp/tailscale /var/task/tailscale

# Run on container startup.
EXPOSE 8080
ENTRYPOINT ["/var/runtime/custom_entrypoint"]
CMD [ "haaska.event_handler" ]
