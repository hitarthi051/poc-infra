#!/bin/bash
set -e

DOMAIN="bg.infra.cpo-uk.icpo.altosaint.co.uk"
REGION="eu-west-1"

VERSION=$(aws lambda get-alias --function-name poc-serverless-typescript-dev-api --name green --query 'FunctionVersion' --output text) && \
aws lambda update-alias --function-name poc-serverless-typescript-dev-api --name prod --function-version "$VERSION"

#!/bin/bash
set -e

# === CONFIGURATION ===
DIST_BLUE="E1T632SM7O8KE3"   # 🔵 Blue distribution ID
DIST_GREEN="E3SGG9AJJ3ROLH"  # 🟢 Green distribution ID
ZONE_ID="Z09957721W0YI639HY837"    # Hosted zone for domain
CNAME_WEC="wec.infra.cpo-uk.icpo.altosaint.co.uk"
CNAME_WILDCARD="*.infra.cpo-uk.icpo.altosaint.co.uk"
TARGET="${STAGE}"  

update_cnames() {
  DIST_ID=$1
  ADD_WEC=$2
  CONF=$(aws cloudfront get-distribution-config --id "$DIST_ID")
  ETAG=$(echo "$CONF" | jq -r .ETag)
  CONFIG=$(echo "$CONF" | jq .DistributionConfig)

  CNAMES=()
  [[ "$DIST_ID" == "$DIST_GREEN" ]] && CNAMES+=("$CNAME_WILDCARD")  # Wildcard always on Green
  [[ "$ADD_WEC" == "true" ]] && CNAMES+=("$CNAME_WEC")

  NEW_CONF=$(echo "$CONFIG" | jq --argjson aliases "$(printf '%s\n' "${CNAMES[@]}" | jq -R . | jq -s '{Quantity: length, Items: .}')" '.Aliases = $aliases')

  aws cloudfront update-distribution \
    --id "$DIST_ID" \
    --if-match "$ETAG" \
    --distribution-config "$NEW_CONF"
}

update_dns() {
  DIST_ID=$1
  DOMAIN_NAME=$(aws cloudfront get-distribution --id "$DIST_ID" --query "Distribution.DomainName" --output text)

  echo "🔄 Updating Route53 to point $CNAME_WEC to $DOMAIN_NAME"

  cat > change-batch.json <<EOF
{
  "Comment": "Switch $CNAME_WEC to CloudFront $DIST_ID",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "$CNAME_WEC",
        "Type": "CNAME",
        "TTL": 300,
        "ResourceRecords": [{ "Value": "$DOMAIN_NAME" }]
      }
    }
  ]
}
EOF

  aws route53 change-resource-record-sets \
    --hosted-zone-id "$ZONE_ID" \
    --change-batch file://change-batch.json

  rm -f change-batch.json
}


if [[ "$TARGET" == "blue" ]]; then
  echo "🔵 Switching $CNAME_WEC to BLUE ($DIST_BLUE)"
  update_cnames "$DIST_BLUE" false
  update_cnames "$DIST_GREEN" false
  update_cnames "$DIST_BLUE" true
  update_dns "$DIST_BLUE"

elif [[ "$TARGET" == "green" ]]; then
  echo "🟢 Switching $CNAME_WEC to GREEN ($DIST_GREEN)"
  update_cnames "$DIST_BLUE" false
  update_cnames "$DIST_GREEN" false
  update_cnames "$DIST_GREEN" true
  update_dns "$DIST_GREEN"

else
  echo "❌ Usage: ./switch-wec.sh [blue|green]"
  exit 1
fi

echo "✅ Successfully switched $CNAME_WEC to $TARGET"


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