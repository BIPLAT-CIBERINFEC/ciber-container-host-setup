FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN echo "postfix postfix/mailname string ciber-smtp-relay" | debconf-set-selections \
    && echo "postfix postfix/main_mailer_type select Satellite system" | debconf-set-selections \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        gettext-base \
        libsasl2-modules \
        postfix \
    && rm -rf /var/lib/apt/lists/*

COPY main.cf.template /etc/postfix/main.cf.template
COPY entrypoint.sh /usr/local/bin/smtp-relay-entrypoint.sh

RUN chmod 0644 /etc/postfix/main.cf.template \
    && chmod 0755 /usr/local/bin/smtp-relay-entrypoint.sh

EXPOSE 25

ENTRYPOINT ["/usr/local/bin/smtp-relay-entrypoint.sh"]
CMD ["postfix", "start-fg"]
