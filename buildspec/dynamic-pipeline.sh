#!/bin/bash

set -e

for id in $(aws cloudfront list-distributions --query "DistributionList.Items[?Tags.Items[?Key=='TrafficType' && Value=='Stable']].Id" --output text); do
  dns=$(aws cloudfront get-distribution --id "$id" --query "Distribution.DomainName" --output text)

  # Get Deployment tag of the stable DNS
  tags=$(aws cloudfront list-tags-for-resource --resource "arn:aws:cloudfront::$(aws sts get-caller-identity --query Account --output text):distribution/$id" --query "Tags.Items" --output json)
  deploy=$(echo "$tags" | jq -r '.[] | select(.Key == "Deployment") | .Value')

  CLOUDFRONT_STABLE="$dns"

  if [[ "$deploy" == "blue" ]]; then
    STABLE_TAG="blue"
    CANARY_TAG="green"    
    CLOUDFRONT_CANARY=$(aws cloudfront list-distributions --query "DistributionList.Items[?Tags.Items[?Key=='Deployment' && Value=='green']].DomainName" --output text)
    UIARTIFACTBUCKETNAME="${UIARTIFACTBUCKETNAME}"
  elif [[ "$deploy" == "green" ]]; then
    STABLE_TAG="green"
    CANARY_TAG="blue"
    CLOUDFRONT_CANARY=$(aws cloudfront list-distributions --query "DistributionList.Items[?Tags.Items[?Key=='Deployment' && Value=='blue']].DomainName" --output text)
    UIARTIFACTBUCKETNAME="${UIARTIFACTBUCKETNAME}-b"
  fi

  break
done


aws cloudformation deploy --template ./dynamic-pipeline.yml \
    --stack-name deployment-dynamic-pipeline \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides \
    APIBranch=${APIBranch} \
    UIARTIFACTBUCKETNAME=${UIARTIFACTBUCKETNAME} \
    BlueOrGreen=${BlueOrGreen} \
    UIBranch=${UIBranch} \
    DEPLOYAPI=${DEPLOYAPI} \
    DEPLOYDB=${DEPLOYDB} \
    DEPLOYUI=${DEPLOYUI} \
    CANARY=${CANARY} \
    HOSTEDZONEID=${HOSTED_ZONE_ID} \
    RECORDNAME=${RECORD_NAME} \
    STABLEWEIGHT=${STABLE_WEIGHT} \
    CANARYWEIGHT=${CANARY_WEIGHT} \
    CLOUDFRONTCANARY=${CLOUDFRONT_CANARY} \
    CLOUDFRONTSTABLE=${CLOUDFRONT_STABLE} \
    STABLETAG=${STABLE_TAG} \
    CANARYTAG=${CANARY_TAG} 
    --no-fail-on-empty-changeset
echo "Deployed Successfully"