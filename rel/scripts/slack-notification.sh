#!/bin/bash

# tweaked from https://gist.github.com/dopiaza/6449505

set -e

if [[ $# -eq 0 ]] ; then
  scriptName=$(basename "$0")
  echo Usage: ./$scriptName "<webhook_url>" "<channel>" "<username>" "<message>"
  exit 0
fi


webhook_url=$1
if [[ $webhook_url == "" ]]
then
  echo "No webhook_url specified"
  exit 1
fi

shift
channel=$1
if [[ $channel == "" ]]
then
  echo "No channel specified"
  exit 1
fi

shift
username=$1
if [[ $username == "" ]]
then
  echo "No username specified"
  exit 1
fi

shift
text=$*

if [[ $text == "" ]]
then
while IFS= read -r line; do
  text="$text$line\\n"
done
fi

if [[ $text == "" ]]
then
  echo "No text specified"
  exit 1
fi

escapedText=$(echo $text | sed 's/"/\"/g' | sed "s/'/\'/g" )

json="{\"channel\": \"$channel\", \"username\":\"$username\", \"icon_emoji\":\":nerves-bot:\", \"attachments\":[{\"color\":\"good \" , \"text\": \"$escapedText\"}]}"

curl -s -d "payload=$json" "$webhook_url"
