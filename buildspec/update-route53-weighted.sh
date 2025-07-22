#!/bin/bash
set -e

DOMAIN="bg.infra.cpo-uk.icpo.altosaint.co.uk"
REGION="eu-west-1"

VERSION=$(aws lambda get-alias --function-name poc-serverless-typescript-dev-api --name green --query 'FunctionVersion' --output text) && \
aws lambda update-alias --function-name poc-serverless-typescript-dev-api --name prod --function-version "$VERSION"

set -e

# === CONFIGURATION ===
DISTRIBUTION_ID_BLUE="E1T632SM7O8KE3"   # 🔵 Blue distribution ID
DISTRIBUTION_ID_GREEN="E3SGG9AJJ3ROLH"  # 🟢 Green distribution ID
ZONE_ID="Z09957721W0YI639HY837"    # Hosted zone for domain
DOMAIN_NAME="wec.infra.cpo-uk.icpo.altosaint.co.uk"
TARGET="${STAGE}"  
if [ "$TARGET" == "blue" ]; then
  ADD_TO=$DISTRIBUTION_ID_BLUE
  REMOVE_FROM=$DISTRIBUTION_ID_GREEN
elif [ "$TARGET" == "green" ]; then
  ADD_TO=$DISTRIBUTION_ID_GREEN
  REMOVE_FROM=$DISTRIBUTION_ID_BLUE
else
  echo "Invalid TARGET: $TARGET. Use 'blue' or 'green'"
  exit 1
fi


echo "Removing $DOMAIN_NAME from $REMOVE_FROM..."
aws cloudfront get-distribution-config --id "$REMOVE_FROM" > remove.json
ETAG_REMOVE=$(aws cloudfront get-distribution-config --id "$REMOVE_FROM" --query "ETag" --output text)

jq --arg domain "$DOMAIN_NAME" '
  .DistributionConfig.Aliases.Items |= map(select(. != $domain)) |
  .DistributionConfig.Aliases.Quantity = (.DistributionConfig.Aliases.Items | length)
' remove.json > remove-updated.json

aws cloudfront update-distribution \
  --id "$REMOVE_FROM" \
  --if-match "$ETAG_REMOVE" \
  --distribution-config file://remove-updated.json
echo "Removed from $REMOVE_FROM ✅"

# === Add to target distribution ===
echo "Adding $DOMAIN_NAME to $ADD_TO..."
aws cloudfront get-distribution-config --id "$ADD_TO" > add.json
ETAG_ADD=$(aws cloudfront get-distribution-config --id "$ADD_TO" --query "ETag" --output text)

jq --arg domain "$DOMAIN_NAME" '
  .DistributionConfig.Aliases.Items |= (.+ [$domain] | unique) |
  .DistributionConfig.Aliases.Quantity = (.DistributionConfig.Aliases.Items | length)
' add.json > add-updated.json

aws cloudfront update-distribution \
  --id "$ADD_TO" \
  --if-match "$ETAG_ADD" \
  --distribution-config file://add-updated.json
echo "Added to $ADD_TO ✅"

# === Clean up ===
rm remove.json remove-updated.json add.json add-updated.json


ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
CANARY_ID=$(aws cloudfront list-distributions \
  --query "DistributionList.Items[?DomainName=='$CLOUDFRONT_CANARY'].Id" \
  --output text)
STABLE_ID=$(aws cloudfront list-distributions \
  --query "DistributionList.Items[?DomainName=='$CLOUDFRONT_STABLE'].Id" \
  --output text)

aws cloudfront tag-resource \
  --resource "arn:aws:cloudfront::$ACCOUNT_ID:distribution/$CANARY_ID" \
  --tags "Items=[{Key=TrafficType,Value=Stable}]"

# ,{Key=Deployment,Value=$STABLE_TAG}
# ,{Key=Deployment,Value=$CANARY_TAG}
aws cloudfront tag-resource \
  --resource "arn:aws:cloudfront::$ACCOUNT_ID:distribution/$STABLE_ID" \
  --tags "Items=[{Key=TrafficType,Value=Canary}]"

  #  aws lambda add-permission --function-name "arn:aws:lambda:eu-west-1:057297422439:function:poc-serverless-typescript-dev-api:prod" --source-arn "arn:aws:execute-api:eu-west-1:057297422439:693utogn2j" --principal apigateway.amazonaws.com --statement-id 78cb2b59-2666-4da5-9004-45d7c3c515fe --action lambda:InvokeFunction