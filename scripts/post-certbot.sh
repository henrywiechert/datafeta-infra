#!/usr/bin/env bash
# Certbot post-renewal hook — reloads Nginx after a certificate is renewed.
# Symlinked (by setup-vps.sh) to:
#   /etc/letsencrypt/renewal-hooks/post/reload-nginx.sh

set -euo pipefail

nginx -s reload
echo "[certbot-hook] Nginx reloaded after certificate renewal"
