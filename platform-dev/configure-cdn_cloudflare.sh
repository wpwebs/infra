# Script automates configure a CDN with Cloudflare using an API token

# Explanation
# 1. Variables:
#     * API_TOKEN: Your Cloudflare API token.
#     * ZONE_ID: The ID of your Cloudflare zone (you can get this from your Cloudflare dashboard).
#     * DOMAIN: Your domain name.
#     * EMAIL: Your email associated with Cloudflare account.
#     * CLOUDFLARE_API: The base URL for the Cloudflare API.
# 2. Functions:
#     * create_dns_record: This function creates a DNS record (A or CNAME) and sets it to be proxied through Cloudflare.
#     * enable_cloudflare_features: This function enables specific Cloudflare features like security level and SSL.
# 3. Main Script:
#     * Calls the functions to create DNS records for the root domain and www subdomain.
#     * Enables desired Cloudflare features.

#!/bin/bash

# Variables - Update these with your details
API_TOKEN="your-cloudflare-api-token"
ZONE_ID="your-zone-id"
DOMAIN="your-domain.com"
EMAIL="your-email@example.com"
CLOUDFLARE_API="https://api.cloudflare.com/client/v4"

# Function to create a DNS record
create_dns_record() {
  local record_type=$1
  local record_name=$2
  local record_content=$3
  local proxied=$4

  curl -X POST "${CLOUDFLARE_API}/zones/${ZONE_ID}/dns_records" \
    -H "Authorization: Bearer ${API_TOKEN}" \
    -H "Content-Type: application/json" \
    --data '{
      "type": "'"${record_type}"'",
      "name": "'"${record_name}"'",
      "content": "'"${record_content}"'",
      "proxied": '"${proxied}"'
    }'
}

# Function to enable Cloudflare features
enable_cloudflare_features() {
  curl -X PATCH "${CLOUDFLARE_API}/zones/${ZONE_ID}/settings/security_level" \
    -H "Authorization: Bearer ${API_TOKEN}" \
    -H "Content-Type: application/json" \
    --data '{"value":"high"}'

  curl -X PATCH "${CLOUDFLARE_API}/zones/${ZONE_ID}/settings/ssl" \
    -H "Authorization: Bearer ${API_TOKEN}" \
    -H "Content-Type: application/json" \
    --data '{"value":"full"}'
}

# Main script
echo "Configuring Cloudflare for ${DOMAIN}..."

# Add A record for the domain
create_dns_record "A" "${DOMAIN}" "your-server-ip" true

# Add CNAME record for www subdomain
create_dns_record "CNAME" "www.${DOMAIN}" "${DOMAIN}" true

# Enable Cloudflare features
enable_cloudflare_features

echo "Cloudflare configuration for ${DOMAIN} is complete."
