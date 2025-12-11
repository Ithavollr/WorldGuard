#!/bin/bash

# --- Configuration ---
# You can customize the default increment behavior here (e.g., patch, minor, major)
DEFAULT_INCREMENT="patch"
# Function to extract the last part of the version (e.g., 2 from v1.2.2)
get_last_version_part() {
    echo "$1" | sed -E "s/.*\.([0-9]+)$/\1/"
}
# --- Determine the correct SED command (GNU sed vs BSD sed) ---
if command -v gsed &>/dev/null; then
    # GNU sed found (common on macOS via Homebrew)
    SED_CMD="gsed"
elif command -v sed &>/dev/null; then
    # Standard sed found (default on Linux and macOS)
    SED_CMD="sed"
else
    echo "Error: Neither 'gsed' nor 'sed' was found on your system." >&2
    exit 1
fi
echo "Using SED command: $SED_CMD"

# Function to suggest the next version based on the current one
suggest_next_version() {
    local current_tag="$1"
    local increment_type="$2"
    local major minor patch
    local version_only

    # Remove the 'v' prefix if present for parsing
    version_only=$(echo "$current_tag" | $SED_CMD "s/^v//")

    # Split the version into components: major, minor, patch
    IFS='.' read -r major minor patch <<< "$version_only"

    if [ -z "$major" ] || [ -z "$minor" ] || [ -z "$patch" ]; then
        # If parsing fails or tag format is non-standard, suggest v1.0.0
        echo "v1.0.0"
        return
    fi

    # Determine the next version based on the increment type
    case "$increment_type" in
        major)
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        minor)
            minor=$((minor + 1))
            patch=0
            ;;
        patch|*)
            patch=$((patch + 1))
            ;;
    esac

    echo "${major}.${minor}.${patch}"
}


# 1. Find the latest tag
LATEST_TAG=$(git describe --tags --abbrev=0 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$LATEST_TAG" ]; then
    echo "No existing Git tags found in this repository."
    LATEST_TAG="none"
    SUGGESTED_TAG="1.0.0"
else
    echo "Latest existing tag found: $LATEST_TAG"
    SUGGESTED_TAG=$(suggest_next_version "$LATEST_TAG" "$DEFAULT_INCREMENT")
fi

echo "---"

# 2. Ask the user for the new tag
while true; do
    read -rp "Enter the NEW tag name (e.g. v1.0.0) [Default: v$SUGGESTED_TAG]: " NEW_TAG_INPUT

    # Use the suggested tag if input is empty
    if [ -z "$NEW_TAG_INPUT" ]; then
        VERSION="$SUGGESTED_TAG"
        NEW_TAG="v$SUGGESTED_TAG"
    else
        VERSION=$(echo "$NEW_TAG_INPUT" | $SED_CMD "s/^v//")
        NEW_TAG="$NEW_TAG_INPUT"
    fi

    # Validate that the new tag doesn't already exist
    if git rev-parse -q --verify "refs/tags/$NEW_TAG" >/dev/null; then
        echo "Error: Tag '$NEW_TAG' already exists in the local repository. Please choose a different name."
        NEW_TAG_INPUT="" # Clear input to re-enter loop
        continue
    fi

    echo "---"
    echo "✨ Proposed Tag: $NEW_TAG"
    read -rp "Is this correct? (y/n): " CONFIRMATION

    case "$CONFIRMATION" in
        [yY]|[yY][eE][sS])
            break
            ;;
        [nN]|[nN][oO])
            echo "---"
            echo "Restarting tag selection..."
            NEW_TAG_INPUT="" # Clear input to re-enter loop
            continue
            ;;
        *)
            echo "Invalid input. Please enter 'y' or 'n'."
            ;;
    esac
done

# 3. Apply the new tag
echo $VERSION > VERSION
$SED_CMD -E -i "s/version=[0-9]+\.[0-9]+\.[0-9]+-SEED/version=$VERSION-SEED/" gradle.properties
echo "Creating release commit..."
git commit -am "RELEASE: $NEW_TAG"
echo "Applying tag '$NEW_TAG' to the current commit..."
git tag "$NEW_TAG"

if [ $? -eq 0 ]; then
    echo "✅ Success! Tag '$NEW_TAG' applied locally."
    echo "uploading release..."
    git push --tags
    git push
else
    echo "❌ Failed to apply tag '$NEW_TAG'. Check your git status."
fi

# Clean up temporary variables
unset LATEST_TAG NEW_TAG_INPUT NEW_TAG SUGGESTED_TAG CONFIRMATION
