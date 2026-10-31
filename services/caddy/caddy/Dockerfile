# Caddy with the Cloudflare DNS plugin.
#
# The official caddy image has no DNS providers compiled in, and this stack
# MUST use DNS-01: the hostnames resolve to a Tailscale 100.x address that
# Let's Encrypt cannot reach from the internet, so HTTP-01 can never work.
#
# Built here rather than pulled from a third party. This binary terminates
# TLS for every service and holds the Cloudflare token; it is worth knowing
# exactly what went into it. Both versions are pinned on purpose.
FROM caddy:2.11.4-builder AS builder
RUN xcaddy build \
      --with github.com/caddy-dns/cloudflare@v0.2.4

FROM caddy:2.11.4
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
