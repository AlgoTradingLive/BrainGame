#!/bin/bash

# Step 1: Keystore बनवा
keytool -genkey -v -keystore braingame-release.jks \
  -alias braingame \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -dname "CN=BrainGame, OU=Dev, O=AlgoTradingLive, L=Mumbai, S=Maharashtra, C=IN" \
  -storepass braingame123 \
  -keypass braingame123

# Step 2: Base64 output
echo ""
echo "====== COPY THIS BASE64 ======"
base64 -w 0 braingame-release.jks
echo ""
echo "=============================="

