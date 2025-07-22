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

remove_cname_from_dist() {
  DIST_ID=$1
  CNAME=$2

  echo "Checking for $CNAME in $DIST_ID..."
  CONF=$(aws cloudfront get-distribution-config --id "$DIST_ID")
  ETAG=$(echo "$CONF" | jq -r .ETag)
  CONFIG=$(echo "$CONF" | jq .DistributionConfig)

  # Remove cname if exists
  CNAMES=$(echo "$CONFIG" | jq '.Aliases.Items')
  NEW_CNAMES=$(echo "$CNAMES" | jq --arg cname "$CNAME" 'map(select(. != $cname))')
  COUNT=$(echo "$NEW_CNAMES" | jq 'length')

  UPDATED=$(echo "$CONFIG" | jq \
    --argjson new_cnames "$NEW_CNAMES" \
    --argjson count "$COUNT" \
    '.Aliases.Items = $new_cnames | .Aliases.Quantity = $count')

  # Send full config
  echo "$UPDATED" > /tmp/conf.json
  aws cloudfront update-distribution \
    --id "$DIST_ID" \
    --if-match "$ETAG" \
    --distribution-config file:///tmp/conf.json

  echo "Removed $CNAME from $DIST_ID"
}

add_cname_to_dist() {
  DIST_ID=$1
  CNAME=$2

  echo "Adding $CNAME to $DIST_ID..."
  CONF=$(aws cloudfront get-distribution-config --id "$DIST_ID")
  ETAG=$(echo "$CONF" | jq -r .ETag)
  CONFIG=$(echo "$CONF" | jq .DistributionConfig)

  # Append cname if not present
  CNAMES=$(echo "$CONFIG" | jq '.Aliases.Items')
  EXISTS=$(echo "$CNAMES" | jq --arg cname "$CNAME" 'index($cname)')

  if [[ "$EXISTS" == "null" ]]; then
    NEW_CNAMES=$(echo "$CNAMES" | jq --arg cname "$CNAME" '. + [$cname]')
    COUNT=$(echo "$NEW_CNAMES" | jq 'length')

    UPDATED=$(echo "$CONFIG" | jq \
      --argjson new_cnames "$NEW_CNAMES" \
      --argjson count "$COUNT" \
      '.Aliases.Items = $new_cnames | .Aliases.Quantity = $count')

    echo "$UPDATED" > /tmp/conf.json
    aws cloudfront update-distribution \
      --id "$DIST_ID" \
      --if-match "$ETAG" \
      --distribution-config file:///tmp/conf.json

    echo "Added $CNAME to $DIST_ID"
  else
    echo "$CNAME already exists in $DIST_ID"
  fi
}

if [[ "$TARGET" == "blue" ]]; then
  remove_cname_from_dist "$GREEN_DIST_ID" "$CNAME_WEC"
  add_cname_to_dist "$BLUE_DIST_ID" "$CNAME_WEC"
elif [[ "$TARGET" == "green" ]]; then
  remove_cname_from_dist "$BLUE_DIST_ID" "$CNAME_WEC"
  add_cname_to_dist "$GREEN_DIST_ID" "$CNAME_WEC"
else
  echo "Invalid target: $TARGET (use 'blue' or 'green')"
  exit 1
fi



# tag
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