#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

docker build -t localimage $SCRIPT_DIR/image
docker build -t fastapi $SCRIPT_DIR/fastapi

TARGET=sample:v1
REGISTRIES=(acrkhcnm acryaxtt)

for REGISTRY in ${REGISTRIES[@]}; do
  az acr login -n $REGISTRY
  
  # nginx w/ tools
  docker tag localimage $REGISTRY.azurecr.io/$TARGET
  docker push $REGISTRY.azurecr.io/$TARGET

  # fastapi app
  docker tag fastapi $REGISTRY.azurecr.io/fastapi
  docker push $REGISTRY.azurecr.io/fastapi
done
