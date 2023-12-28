#!/bin/bash

function checkSession() {
  if [[ -f output.json ]] && [[ -s output.json ]]; then
  read -p "Continue with previous progress? (y/n)" choice
    case "$choice" in
    [yY][eE][sS]|[yY])
      loadSession
    ;;
    [nN][oO]|[nN])
      newSession
    ;;
    *) echo "Invalid input"; exit 1;;
    esac
  else
    newSession
  fi 
}

function newSession() {
  # Initialize an empty JSON object
  jsonObject="{}"

  # Ask for the repository URL
  echo "Please enter the repository URL:"
  read repoURL

  # Clone the repository
  git clone $repoURL

  # Initialize a counter
  counter=0
}

function loadSession() {
  # Load the JSON object
  jsonObject=$(cat output.json)

  # Get the last processed tag
  lastTag=$(echo $jsonObject | jq -r '.lastTag')

  # Get the repository URL
  repoURL=$(echo $jsonObject | jq -r '.repoURL')

  # Get the counter value
  counter=$(echo $jsonObject | jq -r '.counter')
}

function cloneRepo() {
  # Extract the repository name from the URL
  repoName=$(basename $repoURL .git)
  
  # Extract the repository name and owner from the URL
  repoFullName=$(echo $repoURL | awk -F/ '{print $(NF-1)"/"$(NF)}' | sed 's/.git$//')

  # Change to the cloned directory
  pushd $repoName "$@" > /dev/null

  # Fetch the list of tags
  tags=$(git tag)

  # Check if there are tags
  if [[ -z "$tags" ]]; then
    echo "No tags found."
    exit 1
  fi

  # Create the Releases directory within the cloned repository
  mkdir -p Releases
}

function cloneTags() {
  #Loop for each tag
  for tag in ${tags[@]}; do
    
    # Skip the tag if it has been processed
    if [[ " ${lastTag[@]} " =~ " ${tag} " ]]; then
      let counter++
      continue
    fi

    # Fetch the release from GitHub
    while true; do
      get=$(curl -s -i https://api.github.com/repos/$repoFullName/releases/tags/$tag)
      statusCode=$(echo "$get" | head -n 1 | cut -d' ' -f2)
      response=$(echo "$get" | sed -n '/^{/,/}$/p')
      # API Rate limit check
      if [[ $statusCode == 403 || $statusCode == 429 ]]; then
        echo "API Rate limited, try Authenticating or leave this script for an hour to auto-rerun. Press any key to retry now..."
        read -n 1 -s -t 3601
        continue
      else
        break
      fi
    done
    title=$(echo $response | jq -r '.name')

    # Check if the tag is a release
    if [[ $statusCode == 404 ]]; then
      echo "Downloading tag: $tag Not a Release"
      curl -s -L -o "Releases/$tag.zip" "https://github.com/$repoFullName/archive/refs/tags/$tag.zip"
      continue
  
    # Other status code check
    elif [[ $statusCode != 200 ]]; then
      echo "Unknown error, status code: $statusCode tag: $tag"
      continue
    fi

    # If title is null append with tag
    title=${title:-NoTitle-$tag}

    # Console log progress
    echo "Downloading tag: $tag Titled: $title Type: $(git cat-file -t $tag)"

    # Archive the tag into a zip file
    git archive --format=zip --output="Releases/$tag.zip" $tag

    # Create a directory for the release
    mkdir -p "Releases/$title"

    # Move the zip file into the release directory
    mv "Releases/$tag.zip" "Releases/$title/"

    # Download the assets from the release
    gh release download $tag -D "Releases/$title"

    # Update the JSON object
    jsonObject=$(echo $jsonObject | jq --arg repoURL "$repoURL" --arg tag "$tag" --arg response "$response" --arg counter "$counter" '. += {("lastTag"): $tag, ("repoURL"): $repoURL, ("response"): $response, ("counter"): $counter}')

    # Break the loop if all tags have been processed
    if (( counter == ${#tags[@]} )); then
      break
    fi
  done
}

checkSession
cloneRepo
cloneTags

# Save the session
popd "$@" > /dev/null
echo $jsonObject | jq '.' > output.json