CHARTS_PATH="charts"
CHART_VERSION="$(cat CHART_VERSION)"
FORMAT=sha
echo "---Setting chart version as ${CHART_VERSION}---"

# temp-charts will hold the charts until it is ready to replace the current charts dir
mkdir temp-charts

while IFS=, read -r url chartpath shaorbranch
do

  if [[ $shaorbranch == master ]] || [[ $shaorbranch == release* ]];then
    # This is a branch
    printf "\tGithub URL: $url\n\tPath to chart: $chartpath\n\tDesired branch: $shaorbranch\n"
    FORMAT=branch
  else
    # Must be a sha
    printf "\tGithub URL: $url\n\tPath to chart: $chartpath\n\tDesired sha: $shaorbranch\n"
    FORMAT=sha
  fi

  # currentsha is the sha of the chart currently bundled in the charts dir
  currentsha=$(grep --max-count=1 "$url" currentSHAs.csv | cut -d ',' -f3)
  # filename is the desired chart package name
  filename="${chartpath##*/}-${CHART_VERSION}.tgz"

  # Check if chart is using correct sha and chart version
  if [ $FORMAT == sha ] && [ "$currentsha" == "$shaorbranch" ] && [ -f "charts/${filename}" ]; then
    echo $"Current sha matches desired sha and chart file exists. Copying to chart over."
    cp "charts/${filename}" "temp-charts/${filename}"
    echo -en "$url,$chartpath,$shaorbranch\n" >> temp-currentSHAs.csv
    continue
  fi

  if [ $FORMAT == branch ]; then
    ## Check most recent sha in the repository branch

    httpsTrimmedURL=${url#*//}
    # githubTrimmedURL is the repo name without the leading 'https://github.com/'
    githubTrimmedURL=${httpsTrimmedURL#*/}
    echo $githubTrimmedURL

    lastsha=$(curl -s -H "Accept: application/vnd.github.v3+json" https://api.github.com/repos/${githubTrimmedURL}/git/refs/heads/${shaorbranch} | jq -r '.object.sha')
    if [ "$currentsha" == "$lastsha" ] && [ -f "charts/${filename}" ]; then
      # We already have this sha so no need to repackage
      echo "Latest SHA matches SHA in branch ${shaorbranch} and file chart version exists."
      cp "charts/${filename}" "temp-charts/${filename}"
      echo -en "$url,$chartpath,$lastsha\n" >> temp-currentSHAs.csv
      continue
    fi
  fi

  echo "$url either does not have desired sha, doesn't have latest sha, or isn't set to the current chart version. It will need to be repackaged."

  # Work in temporary directory
  mkdir -p tmp
  cd tmp
  # Clone repo
  git clone $url
  # Enter repo directory
  cd */
  # Checkout branch or commit sha from origin
  git checkout $shaorbranch
  lastsha=$(git rev-parse HEAD)
  echo "Most recent sha is ${lastsha}"

  helm package $chartpath --version="${CHART_VERSION}" --destination="../../temp-charts"

  cd ../..
  rm -rf tmp
  echo -en "$url,$chartpath,$lastsha\n" >> temp-currentSHAs.csv
done < desiredSHAs.csv

# cp "${CHARTS_PATH}/index.yaml" temp-charts/index.yaml
rm -rf ${CHARTS_PATH}
mv temp-charts ${CHARTS_PATH}
mv temp-currentSHAs.csv currentSHAs.csv
git status --porcelain
