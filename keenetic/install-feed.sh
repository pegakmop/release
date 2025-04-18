#!/bin/sh

echo "Updating package list..."
opkg update

echo "Installing wget with HTTPS support..."
opkg install wget-ssl curl vim nano ca-certificates
opkg remove wget-nossl

echo "Detecting system architecture (via opkg)..."
ARCH=$(opkg print-architecture | awk '
  /^arch/ && $2 !~ /_kn$/ && $2 ~ /-[0-9]+\.[0-9]+$/ {
    print $2; exit
  }'
)

if [ -z "$ARCH" ]; then
  echo "Failed to detect architecture."
  exit 1
fi

case "$ARCH" in
  aarch64-3.10)
    FEED_URL="https://pegakmop.github.io/release/keenetic/aarch64-k3.10"
    ;;
  mipsel-3.4)
    FEED_URL="https://pegakmop.github.io/release/keenetic/mipselsf-k3.4"
    ;;
  mips-3.4)
    FEED_URL="https://pegakmop.github.io/release/keenetic/mipssf-k3.4"
    ;;
  *)
    echo "Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

echo "Architecture detected: $ARCH"
echo "Selected feed: $FEED_URL"

FEED_CONF="/opt/etc/opkg/customfeeds.conf"
FEED_LINE="src/gz pegakmop $FEED_URL"

# Ensure the opkg directory exists
if [ ! -d "/opt/etc/opkg" ]; then
  echo "Creating /opt/etc/opkg directory..."
  mkdir -p /opt/etc/opkg
fi

# Check for existing feed entry
if grep -q "$FEED_URL" "$FEED_CONF" 2>/dev/null; then
  echo "Repository already present in $FEED_CONF. Skipping."
else
  echo "Adding repository to $FEED_CONF..."
  echo "$FEED_LINE" >> "$FEED_CONF"
fi

echo "Updating package list again (with custom feed)..."
opkg update

#echo "Install hydra command: 'opkg install hrneo' & 'opkg install hydraroute' router package..."
#opkg install hrneo || echo "Package 'hrneo' & 'hydraroute' not found in feed. Skipping."
echo "Для установки достаточно команды:"
echo "opkg install hrneo"
echo "системный днс кинетика используется"
echo "или"
echo "opkg install hydraroute"
echo "адгуард как системный днс(аля бета2)"

# Optional cleanup
SCRIPT="$0"
if [ -f "$SCRIPT" ]; then
  echo "- Cleaning up installer script..."
  rm "$SCRIPT"
fi

echo "Setup custom repository complete."
