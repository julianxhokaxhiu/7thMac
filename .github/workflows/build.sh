#!/bin/bash

#*****************************************************************************#
#    Copyright (C) 2026 Julian Xhokaxhiu                                      #
#                                                                             #
#    This file is part of SummonKit                                           #
#                                                                             #
#    SummonKit is free software: you can redistribute it and\or modify        #
#    it under the terms of the GNU General Public License as published by     #
#    the Free Software Foundation, either version 3 of the License            #
#                                                                             #
#    SummonKit is distributed in the hope that it will be useful,             #
#    but WITHOUT ANY WARRANTY; without even the implied warranty of           #
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the            #
#    GNU General Public License for more details.                             #
#*****************************************************************************#

set -euo pipefail

if [[ "$_BUILD_BRANCH" == "refs/heads/master" || "$_BUILD_BRANCH" == "refs/tags/canary" ]]; then
  export _IS_BUILD_CANARY="true"
  export _IS_GITHUB_RELEASE="true"
elif [[ "$_BUILD_BRANCH" == refs/tags/* ]]; then
  _BUILD_VERSION="${_BUILD_VERSION%-*}.0"
  export _BUILD_VERSION
  export _IS_GITHUB_RELEASE="true"
fi
export _RELEASE_VERSION="v${_BUILD_VERSION}"

echo "--------------------------------------------------"
echo "RELEASE VERSION: $_RELEASE_VERSION"
echo "--------------------------------------------------"

echo "_BUILD_VERSION=${_BUILD_VERSION}" >> "${GITHUB_ENV}"
echo "_RELEASE_VERSION=${_RELEASE_VERSION}" >> "${GITHUB_ENV}"
echo "_IS_BUILD_CANARY=${_IS_BUILD_CANARY}" >> "${GITHUB_ENV}"
echo "_IS_GITHUB_RELEASE=${_IS_GITHUB_RELEASE}" >> "${GITHUB_ENV}"

npm install --global create-dmg

echo "--------------------------------------------------"
echo " Building and packaging 7th Heaven"
echo "--------------------------------------------------"

./7thHeaven/build_app.sh --dist ./dist
create-dmg --no-code-sign dist/7thHeaven.app dist/

echo "--------------------------------------------------"
echo " Building and packaging Junction VIII"
echo "--------------------------------------------------"

./JunctionVIII/build_app.sh --dist ./dist
create-dmg --no-code-sign dist/JunctionVIII.app dist/
