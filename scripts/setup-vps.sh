#!/usr/bin/env bash
# One-time VPS setup for datafeta.io.
# Run as root directly on the VPS: sudo bash setup-vps.sh
#
# Idempotent — safe to run more than once.
# Prerequisites: Ubuntu 22.04+, Nginx + certbot already installed.

set -euo pipefail

DEPLOY_USER=deploy
INFRA_REPO=https://github.com/henrywiechert/datafeta-infra.git
INFRA_DIR=/opt/datafeta-infra
DATA_DIR=/opt/datafeta-data

# ── Guard ────────────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo "Run as root: sudo bash $0" >&2
    exit 1
fi

# ── Step 1: Create deploy user ───────────────────────────────────────────────
echo "=== Step 1: deploy user ==="
if ! id "$DEPLOY_USER" &>/dev/null; then
    useradd -m -s /bin/bash "$DEPLOY_USER"
    echo "  Created user: $DEPLOY_USER"
else
    echo "  User $DEPLOY_USER already exists"
fi

mkdir -p "/home/$DEPLOY_USER/.ssh"
chmod 700 "/home/$DEPLOY_USER/.ssh"
touch "/home/$DEPLOY_USER/.ssh/authorized_keys"
chmod 600 "/home/$DEPLOY_USER/.ssh/authorized_keys"
chown -R "$DEPLOY_USER:$DEPLOY_USER" "/home/$DEPLOY_USER/.ssh"

cat <<'EOF'

  ┌─ MANUAL STEP ─────────────────────────────────────────────────────────────┐
  │ Generate an SSH key pair on your LOCAL machine (not on the VPS):          │
  │                                                                            │
  │   ssh-keygen -t ed25519 -C "datafeta-deploy" -f ~/.ssh/datafeta_deploy    │
  │                                                                            │
  │ Add the PUBLIC key to the deploy user's authorized_keys:                  │
  │                                                                            │
  │   cat ~/.ssh/datafeta_deploy.pub >> /home/deploy/.ssh/authorized_keys     │
  │                                                                            │
  │ Add the PRIVATE key as GitHub Secret VPS_SSH_KEY in both repos:           │
  │   cat ~/.ssh/datafeta_deploy                                               │
  └───────────────────────────────────────────────────────────────────────────┘

EOF

# ── Step 2: Install Docker ───────────────────────────────────────────────────
echo "=== Step 2: Docker ==="
if ! command -v docker &>/dev/null; then
    apt-get update -q
    apt-get install -y -q ca-certificates curl gnupg
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
        | tee /etc/apt/sources.list.d/docker.list >/dev/null
    apt-get update -q
    apt-get install -y -q docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin
    echo "  Docker installed"
else
    echo "  Docker already installed: $(docker --version)"
fi

usermod -aG docker "$DEPLOY_USER"
echo "  Added $DEPLOY_USER to docker group"

# ── Step 3: Create directories ───────────────────────────────────────────────
echo "=== Step 3: Directories ==="
mkdir -p "$INFRA_DIR" "$DATA_DIR/snapshots"
chown -R "$DEPLOY_USER:$DEPLOY_USER" "$INFRA_DIR" "$DATA_DIR"
echo "  $INFRA_DIR"
echo "  $DATA_DIR/snapshots"

# ── Step 4: Clone infra repo ─────────────────────────────────────────────────
echo "=== Step 4: Infra repo ==="
if [[ ! -d "$INFRA_DIR/.git" ]]; then
    sudo -u "$DEPLOY_USER" git clone "$INFRA_REPO" "$INFRA_DIR"
    echo "  Cloned $INFRA_REPO → $INFRA_DIR"
else
    chown -R "$DEPLOY_USER:$DEPLOY_USER" "$INFRA_DIR"
    sudo -u "$DEPLOY_USER" git -C "$INFRA_DIR" pull --ff-only
    echo "  Already cloned — ownership repaired and pulled latest"
fi

# ── Step 5: Create .env ──────────────────────────────────────────────────────
echo "=== Step 5: .env ==="
if [[ ! -f "$INFRA_DIR/.env" ]]; then
    cp "$INFRA_DIR/.env.example" "$INFRA_DIR/.env"
    chown "$DEPLOY_USER:$DEPLOY_USER" "$INFRA_DIR/.env"
    echo "  Created $INFRA_DIR/.env from example — review and edit if needed"
else
    echo "  .env already exists"
fi

# ── Step 6: Nginx configs ────────────────────────────────────────────────────
echo "=== Step 6: Nginx ==="
cp "$INFRA_DIR/nginx/app.conf"     /etc/nginx/sites-available/datafeta-app
cp "$INFRA_DIR/nginx/website.conf" /etc/nginx/sites-available/datafeta-website
ln -sf /etc/nginx/sites-available/datafeta-app     /etc/nginx/sites-enabled/datafeta-app
ln -sf /etc/nginx/sites-available/datafeta-website /etc/nginx/sites-enabled/datafeta-website
nginx -t
systemctl reload nginx
echo "  Nginx configs installed and reloaded"

# ── Step 7: Certbot renewal hook ─────────────────────────────────────────────
echo "=== Step 7: Certbot renewal hook ==="
mkdir -p /etc/letsencrypt/renewal-hooks/post
cp "$INFRA_DIR/scripts/post-certbot.sh" \
    /etc/letsencrypt/renewal-hooks/post/reload-nginx.sh
chmod +x /etc/letsencrypt/renewal-hooks/post/reload-nginx.sh
echo "  Hook installed at /etc/letsencrypt/renewal-hooks/post/reload-nginx.sh"

# ── Done ─────────────────────────────────────────────────────────────────────
cat <<EOF

=== Setup complete ===

Next manual steps (in order):

  1. Add the deploy user's SSH public key (see box above).

  2. Add GitHub Secrets to BOTH the app and website repos:
       VPS_HOST   = <your VPS IP or hostname>
       VPS_USER   = deploy
       VPS_SSH_KEY = <contents of ~/.ssh/datafeta_deploy>

  3. Run certbot (obtains certs + adds SSL blocks to nginx configs):
       certbot --nginx -d datafeta.io -d www.datafeta.io -d app.datafeta.io

  4. Make the GHCR packages public (or configure Docker login):
       GitHub → your profile → Packages → data-slicer → Package settings → Change visibility → Public
       GitHub → your profile → Packages → datafeta-website → Package settings → Change visibility → Public

  5. First deploy (pull images and start containers):
       sudo -u deploy docker compose -f $INFRA_DIR/docker-compose.prod.yml pull
       sudo -u deploy docker compose -f $INFRA_DIR/docker-compose.prod.yml up -d

  6. Verify:
       curl http://127.0.0.1:8100/api/v1/health   # should return {"status":"ok",...}
       curl http://127.0.0.1:8101/                 # should return website HTML
       curl https://app.datafeta.io/api/v1/health  # after certbot
       curl https://datafeta.io/                   # after certbot

EOF
