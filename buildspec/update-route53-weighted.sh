#!/bin/bash
set -e

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
          "HostedZoneId": "$HOSTED_ZONE_ID",
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
          "HostedZoneId": "$HOSTED_ZONE_ID",
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
  --tags "Items=[{Key=TrafficType,Value=Stable},{Key=Deployment,Value=$STABLE_TAG}]"

aws cloudfront tag-resource \
  --resource "arn:aws:cloudfront::$ACCOUNT_ID:distribution/$STABLE_ID" \
  --tags "Items=[{Key=TrafficType,Value=Canary},{Key=Deployment,Value=$CANARY_TAG}]"