#!/bin/bash
set -e

DOMAIN="bg.infra.cpo-uk.icpo.altosaint.co.uk"
REGION="eu-west-1"

# Delete existing base path mappings
# for path in $(aws apigateway get-base-path-mappings --domain-name "$DOMAIN" --region "$REGION" --query 'items[*].basePath' --output text); do
#   aws apigateway delete-base-path-mapping --domain-name "$DOMAIN" --base-path "$path" --region "$REGION"
# done

# # Create new base path mapping (root)
# aws apigateway create-base-path-mapping \
#   --domain-name "$DOMAIN" \
#   --rest-api-id "$APIID" \
#   --stage "$STAGE" \
#   --base-path "(none)" \
#   --region "$REGION"

echo "✅ Mapping updated: $DOMAIN -> $STAGE"


cat > change-batch.json <<EOF
{
  "Comment": "Weighted routing update",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "$RECORD_NAME",
        "Type": "A",
        "SetIdentifier": "Stable-Version",
        "Weight": $STABLE_WEIGHT,
        "AliasTarget": {
          "HostedZoneId": "Z2FDTNDATAQYW2",
          "DNSName": "$CLOUDFRONT_STABLE",
          "EvaluateTargetHealth": false
        }
      }
    },
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "$RECORD_NAME",
        "Type": "A",
        "SetIdentifier": "Canary-Version",
        "Weight": $CANARY_WEIGHT,
        "AliasTarget": {
          "HostedZoneId": "Z2FDTNDATAQYW2",
          "DNSName": "$CLOUDFRONT_CANARY",
          "EvaluateTargetHealth": false
        }
      }
    }
  ]
}
EOF

aws route53 change-resource-record-sets \
  --hosted-zone-id "$HOSTED_ZONE_ID" \
  --change-batch file://change-batch.json

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
  aws lambda add-permission --function-name "arn:aws:lambda:eu-west-1:057297422439:function:blue-green-api:green" --source-arn "arn:aws:execute-api:eu-west-1:057297422439:693utogn2j/*/GET/get-all-users" --principal apigateway.amazonaws.com --statement-id 78cb2b59-2666-4da5-9004-45d7c3c515fe --action lambda:InvokeFunction