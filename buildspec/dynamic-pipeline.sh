#!/bin/bash

set -e

# STABLE_TAG=""
# CANARY_TAG=""
CLOUDFRONT_CANARY=""
CLOUDFRONT_STABLE=""
# for id in $(aws cloudfront list-distributions --query "DistributionList.Items[?Tags.Items[?Key=='TrafficType' && Value=='Stable']].Id" --output text); do
#   dns=$(aws cloudfront get-distribution --id "$id" --query "Distribution.DomainName" --output text)

#   # Get Deployment tag of the stable DNS
#   tags=$(aws cloudfront list-tags-for-resource --resource "arn:aws:cloudfront::$(aws sts get-caller-identity --query Account --output text):distribution/$id" --query "Tags.Items" --output json)
#   deploy=$(echo "$tags" | jq -r '.[] | select(.Key == "Deployment") | .Value')

#   export CLOUDFRONT_STABLE="$dns"

#   if [[ "$deploy" == "blue" ]]; then
#    export STABLE_TAG="blue"
#    export CANARY_TAG="green"    
#    export CLOUDFRONT_CANARY=$(aws cloudfront list-distributions --query "DistributionList.Items[?Tags.Items[?Key=='Deployment' && Value=='green']].DomainName" --output text)
#    export UIARTIFACTBUCKETNAME="${UIARTIFACTBUCKETNAME}"
#   elif [[ "$deploy" == "green" ]]; then
#     export STABLE_TAG="green"
#     export CANARY_TAG="blue"
#     export CLOUDFRONT_CANARY=$(aws cloudfront list-distributions --query "DistributionList.Items[?Tags.Items[?Key=='Deployment' && Value=='blue']].DomainName" --output text)
#     export UIARTIFACTBUCKETNAME="${UIARTIFACTBUCKETNAME}-b"
#   fi
#    echo "CLOUDFRONT_STABLE: $CLOUDFRONT_STABLE"
#    echo "CLOUDFRONT_CANARY: $CLOUDFRONT_CANARY"
#   break
# done

#!/bin/bash

set -e

account_id=$(aws sts get-caller-identity --query Account --output text)

for id in $(aws cloudfront list-distributions --query "DistributionList.Items[].Id" --output text); do
  arn="arn:aws:cloudfront::${account_id}:distribution/${id}"

  tags=$(aws cloudfront list-tags-for-resource --resource "$arn" --query "Tags.Items" --output json)

  traffic_type=$(echo "$tags" | jq -r '.[] | select(.Key == "TrafficType") | .Value')
  
  if [[ "$traffic_type" == "Stable" ]]; then
    dns=$(aws cloudfront get-distribution --id "$id" --query "Distribution.DomainName" --output text)
    deploy=$(echo "$tags" | jq -r '.[] | select(.Key == "Deployment") | .Value')

    export CLOUDFRONT_STABLE="$dns"

    if [[ "$deploy" == "blue" ]]; then
      export STABLE_TAG="blue"
      export CANARY_TAG="green"
    elif [[ "$deploy" == "green" ]]; then
      export STABLE_TAG="green"
      export CANARY_TAG="blue"
    else
      echo "Unknown deployment tag: $deploy"
      exit 1
    fi

    # Find the canary distribution
    for cid in $(aws cloudfront list-distributions --query "DistributionList.Items[].Id" --output text); do
      carn="arn:aws:cloudfront::${account_id}:distribution/${cid}"
      ctags=$(aws cloudfront list-tags-for-resource --resource "$carn" --query "Tags.Items" --output json)
      cdeploy=$(echo "$ctags" | jq -r '.[] | select(.Key == "Deployment") | .Value')

      if [[ "$cdeploy" == "$CANARY_TAG" ]]; then
        export CLOUDFRONT_CANARY=$(aws cloudfront get-distribution --id "$cid" --query "Distribution.DomainName" --output text)
        break
      fi
    done

    # Artifact bucket name logic
    if [[ "$STABLE_TAG" == "green" ]]; then
      export UIARTIFACTBUCKETNAME="${UIARTIFACTBUCKETNAME}-b"
    fi

    echo "CLOUDFRONT_STABLE: $CLOUDFRONT_STABLE"
    echo "CLOUDFRONT_CANARY: $CLOUDFRONT_CANARY"
    echo "STABLE_TAG: $STABLE_TAG"
    echo "CANARY_TAG: $CANARY_TAG"

    break
  fi
done

echo "CLOUDFRONT_STABLE: $CLOUDFRONT_STABLE"
echo "CLOUDFRONT_CANARY: $CLOUDFRONT_CANARY"


aws cloudformation deploy --template ./dynamic-pipeline.yml \
    --stack-name deployment-dynamic-pipeline \
    --capabilities CAPABILITY_NAMED_IAM \
    --s3-bucket ${S3Bucket} \
    --parameter-overrides \
    APIBranch=${APIBranch} \
    S3Bucket=${S3Bucket} \
    Githubtoken=${Githubtoken} \
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
    APIID=${APIID} \
    CANARYTAG=${CANARY_TAG} \
    --no-fail-on-empty-changeset
echo "Deployed Successfully"