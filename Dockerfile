FROM alpine:3.12

ARG VERSION=dev
ENV AZOPSTFRUN_VERSION=${VERSION}
ENV TF_IN_AUTOMATION 1

RUN apk add --update --no-cache wget ca-certificates unzip bash curl jq

ADD root /

ENTRYPOINT ["/entrypoint.sh"]
