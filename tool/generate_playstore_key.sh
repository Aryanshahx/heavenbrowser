#!/usr/bin/env bash
set -euo pipefail

# Generates a Google Play Store Upload Keystore for Heaven Browser
# and outputs the 4 GitHub Actions Repository Secrets needed for CI signing.

KEY_DIR="${HOME}/heaven-playstore-keys"
KEYSTORE_PATH="${KEY_DIR}/upload-keystore.jks"
SECRETS_FILE="${KEY_DIR}/GITHUB_SECRETS.txt"
KEY_ALIAS="heaven_upload"

mkdir -p "${KEY_DIR}"
chmod 700 "${KEY_DIR}"

if ! command -v keytool >/dev/null 2>&1; then
  echo "Error: 'keytool' not found. Install OpenJDK (sudo apt install -y default-jdk-headless) and re-run." >&2
  exit 1
fi

if [ -f "${KEYSTORE_PATH}" ]; then
  echo "Existing Play Store upload keystore found at: ${KEYSTORE_PATH}"
  echo "Delete or back it up first if you intentionally want to generate a brand-new key."
  exit 0
fi

STORE_PASS="$(dd if=/dev/urandom bs=128 count=1 2>/dev/null | LC_ALL=C tr -dc 'A-Za-z0-9' | cut -c1-24)"
KEY_PASS="${STORE_PASS}"

keytool -genkeypair -v \
  -keystore "${KEYSTORE_PATH}" \
  -storetype PKCS12 \
  -alias "${KEY_ALIAS}" \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -storepass "${STORE_PASS}" \
  -keypass "${KEY_PASS}" \
  -dname "CN=HyperTech Labs, OU=Mobile, O=HyperTech Labs, L=Lucknow, ST=Uttar Pradesh, C=IN"

chmod 600 "${KEYSTORE_PATH}"

KEYSTORE_B64="$(base64 -w 0 "${KEYSTORE_PATH}" 2>/dev/null || base64 "${KEYSTORE_PATH}" | tr -d '\n\r ')"

if [ -d "android/app" ]; then
  cat <<EOF > android/key.properties
storePassword=${STORE_PASS}
keyPassword=${KEY_PASS}
keyAlias=${KEY_ALIAS}
storeFile=${KEYSTORE_PATH}
EOF
  chmod 600 android/key.properties
fi

cat <<EOF > "${SECRETS_FILE}"
====================================================================
HEAVEN BROWSER — GOOGLE PLAY STORE GITHUB ACTIONS SECRETS
Keep upload-keystore.jks backed up safely! Never commit it to Git.
Add these 4 Repository Secrets at:
https://github.com/Aryanshahx/heavenbrowser/settings/secrets/actions
====================================================================

1) Secret Name: ANDROID_KEY_ALIAS
${KEY_ALIAS}

2) Secret Name: ANDROID_KEYSTORE_PASSWORD
${STORE_PASS}

3) Secret Name: ANDROID_KEY_PASSWORD
${KEY_PASS}

4) Secret Name: ANDROID_KEYSTORE_BASE64
${KEYSTORE_B64}
EOF

chmod 600 "${SECRETS_FILE}"

echo ""
echo "Play Store Upload Key generated successfully!"
echo "  Keystore backup : ${KEYSTORE_PATH}"
echo "  GitHub Secrets  : ${SECRETS_FILE}"
echo ""
echo "Open ${SECRETS_FILE} to copy your 4 GitHub Actions secrets."
