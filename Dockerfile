FROM alpine:3.12

ENV AZOPSTFRUN_VERSION dev
ENV TF_IN_AUTOMATION 1

RUN apk add --update --no-cache wget ca-certificates unzip bash curl jq

ADD root /

ENTRYPOINT ["/entrypoint.sh"]