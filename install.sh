#!/bin/sh
# Builds Lumi Connect, installs it in /Applications and the Ableton remote script in the User Library.
# The User Library is read from the most recently used Live's Library.cfg; pass a path to override it.
set -e
cd "$(dirname "$0")"

if [ -n "$1" ]; then
  LIBRARY="$1"
else
  CFG="$(ls -t "$HOME"/Library/Preferences/Ableton/Live\ */Library.cfg 2>/dev/null | head -1)"
  PARENT="$(sed -n '/<UserLibrary>/,/<\/UserLibrary>/s/.*<ProjectPath Value="\([^"]*\)".*/\1/p' "$CFG" 2>/dev/null | head -1)"
  LIBRARY="${PARENT:-$HOME/Music/Ableton}/User Library"
fi
if [ ! -d "$LIBRARY" ]; then
  echo "No User Library at $LIBRARY. Run ./install.sh \"/path/to/User Library\"." >&2
  exit 1
fi

./build.sh
rm -rf "/Applications/Lumi Connect.app"
cp -R "build/Lumi Connect.app" /Applications/
SCRIPTS="$LIBRARY/Remote Scripts"
mkdir -p "$SCRIPTS"
rm -rf "$SCRIPTS/Lumi"
cp -R RemoteScript/Lumi "$SCRIPTS/Lumi"
echo "Installed /Applications/Lumi Connect.app and $SCRIPTS/Lumi"
echo "Restart Ableton Live to load the script."
