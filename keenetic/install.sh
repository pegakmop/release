#!/bin/sh

# Анимация ожидания выполнения команды
animation() {
	local pid=$1
	local message=$2
	local spin='-\|/'

	echo -n "$message... "

	while kill -0 $pid 2>/dev/null; do
		for i in $(seq 0 3); do
			echo -ne "\b${spin:$i:1}"
			usleep 100000  # 0.1 сек
		done
	done

	wait $pid
	if [ $? -eq 0 ]; then
		echo -e "\b✔ Готово!"
	else
		echo -e "\b✖ Ошибка!"
	fi
}

# Обёртка для запуска команды с анимацией
run_with_animation() {
	local message="$1"
	shift
	("$@") &
	animation $! "$message"
}

echo "Starting setup..."

run_with_animation "Updating package list" opkg update

run_with_animation "Installing wget-ssl" opkg install wget-ssl
run_with_animation "Removing wget-nossl" opkg remove wget-nossl

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
    FEED_URL="https://ground-zerro.github.io/release/keenetic/aarch64-k3.10"
    ;;
  mipsel-3.4)
    FEED_URL="https://ground-zerro.github.io/release/keenetic/mipselsf-k3.4"
    ;;
  mips-3.4)
    FEED_URL="https://ground-zerro.github.io/release/keenetic/mipssf-k3.4"
    ;;
  *)
    echo "Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

echo "Architecture detected: $ARCH"
echo "Selected feed: $FEED_URL"

FEED_CONF="/opt/etc/opkg/hydraroute.conf"
FEED_LINE="src/gz HydraRoute $FEED_URL"

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

run_with_animation "Updating package list with custom feed" opkg update

# Prompt user to choose a package to install
echo "Do you want to install 'hydraroute' or 'hrneo'? (Type the name or press Enter to skip):"
read PACKAGE_NAME

case "$PACKAGE_NAME" in
  hydraroute|hrneo)
    run_with_animation "Installing package: $PACKAGE_NAME" opkg install "$PACKAGE_NAME"
    ;;
  *)
    echo "No valid package selected. Skipping installation."
    ;;
esac

# Optional cleanup
SCRIPT="$0"
if [ -f "$SCRIPT" ]; then
  echo "- Cleaning up installer script..."
  rm "$SCRIPT"
fi

echo "Setup complete."
