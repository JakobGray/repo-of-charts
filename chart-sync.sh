CHARTS_PATH="charts/"
CHART_VERSION="$(cat CHART_VERSION)"
echo "Setting chart version as ${CHART_VERSION}"
# rm charts/* #rm all charts first, in case chart versions are changed
mkdir temp-charts

while IFS=, read -r url chartpath shaorbranch
do
  printf "Github URL: $url\nPath to chart: $chartpath\nDesired sha: $shaorbranch\n"

  latestsha=$(grep --max-count=1 "$url" latestSHAs.csv | cut -d ',' -f3)
  filename="${chartpath##*/}-${CHART_VERSION}.tgz"

  # Check if chart is using correct sha and chart version
  if [ "$latestsha" == "$shaorbranch" ] && [ -f "charts/${filename}" ]; then
    echo $"Latest SHA matches desired SHA and file exists. Copying to temp-charts."
    cp "charts/${filename}" "temp-charts/${filename}"
    echo -en "$url,$chartpath,$newsha\n" >> temp-latestSHAs.csv
    continue
  fi

  # Work in temporary directory
  mkdir -p tmp
  cd tmp
  # Clone repo
  git clone $url
  # Enter repo directory
  cd */
  # Checkout branch or commit sha from origin
  git checkout $shaorbranch
  newsha=$(git rev-parse HEAD)
  echo $"New sha is ${newsha}"

  if [ "$latestsha" == "$newsha" ]; then
    echo "Latest SHA matches SHA in branch ${shaorbranch}"
  fi
  if [ -f "../../charts/${filename}" ]; then
    echo "File exists in charts folder"
  fi

  if [ "$latestsha" == "$newsha" ] && [ -f "../../charts/${filename}" ]; then
    # We already have this sha so no need to repackage
    echo "Latest SHA matches SHA in branch ${shaorbranch} and file chart version exists."
    cp "../../charts/${filename}" "../../temp-charts/${filename}"
  else
    echo "Either shas don't match or the chart version has changed. Repackaging helm chart to temp-charts."
    helm package $chartpath --version="${CHART_VERSION}" --destination="../../temp-charts"
  fi

  cd ../..
  rm -rf tmp
  echo -en "$url,$chartpath,$newsha\n" >> temp-latestSHAs.csv
done < desiredSHAs.csv

rm -rf ${CHARTS_PATH}
mv temp-charts ${CHARTS_PATH}
helm repo index --url http://multiclusterhub-repo:3000/charts ${CHARTS_PATH}
mv temp-latestSHAs.csv latestSHAs.csv