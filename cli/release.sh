#!/bin/bash
set -e

cd "$(dirname "$0")"

# Get current version from root.go
CURRENT_VERSION=$(grep 'version.*=' cmd/root.go | head -1 | sed 's/.*"\(.*\)".*/\1/')
echo "Current CLI version: $CURRENT_VERSION"

# Ask for new version
read -p "New version (without 'cli-v' prefix): " NEW_VERSION

if [ -z "$NEW_VERSION" ]; then
  echo "No version provided, exiting."
  exit 1
fi

# Update version in root.go
sed -i '' "s/version.*=.*\"$CURRENT_VERSION\"/version   = \"$NEW_VERSION\"/" cmd/root.go

echo "Updated cli/cmd/root.go to version $NEW_VERSION"

# Commit and tag
cd ..
git add cli/cmd/root.go
git commit -m "chore: release cli v$NEW_VERSION"
git tag "cli-v$NEW_VERSION"

echo ""
echo "Created commit and tag cli-v$NEW_VERSION"
echo ""
read -p "Push to origin? (y/n): " PUSH

if [ "$PUSH" = "y" ]; then
  git push origin main
  git push origin "cli-v$NEW_VERSION"
  echo "Pushed to origin!"
else
  echo "Run manually:"
  echo "  git push origin main"
  echo "  git push origin cli-v$NEW_VERSION"
fi
