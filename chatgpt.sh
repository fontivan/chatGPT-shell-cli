#!/bin/bash

# Error handling function
# $1 should be the response body
handleError() {
	if echo "$1" | jq -e '.error' >/dev/null; then
		echo -e "Your request to Open AI API failed: \033[0;31m$(echo $1 | jq -r '.error.type')\033[0m"
		echo $1 | jq -r '.error.message'
		exit 1
	fi
}
# parse command line arguments
while [[ "$#" -gt 0 ]]; do
	case $1 in
	-t | --temperature)
		TEMPERATURE="$2"
		shift
		shift
		;;
	--max-tokens)
		MAX_TOKENS="$2"
		shift
		shift
		;;
	-m | --model)
		MODEL="$2"
		shift
		shift
		;;
	-s | --size)
		SIZE="$2"
		shift
		shift
		;;
	-c | --context)
		CONTEXT=true
		shift
		shift
		;;
	*)
		echo "Unknown parameter: $1"
		exit 1
		;;
	esac
done

# set defaults
TEMPERATURE=${TEMPERATURE:-0.7}
MAX_TOKENS=${MAX_TOKENS:-1024}
MODEL=${MODEL:-text-davinci-003}
SIZE=${SIZE:-512x512}
CONTEXT=${CONTEXT:-false}

echo -e "Welcome to chatgpt. You can quit with '\033[36mexit\033[0m'."
running=true

# create history file
if [ ! -f ~/.chatgpt_history ]; then
	touch ~/.chatgpt_history
	chmod a+rw ~/.chatgpt_history
fi
# start new session
echo "session-`date '+%Y/%m/%d'`-`date '+%H:%M:%S'`">>~/.chatgpt_history


while $running; do
	echo -e "\nEnter a prompt:"
	read prompt

	if [ "$prompt" == "exit" ]; then
		running=false
	elif [[ "$prompt" =~ ^image: ]]; then
		image_response=$(curl https://api.openai.com/v1/images/generations \
			-sS \
			-H 'Content-Type: application/json' \
			-H "Authorization: Bearer $OPENAI_KEY" \
			-d '{
    		"prompt": "'"${prompt#*image:}"'",
    		"n": 1,
    		"size": "'"$SIZE"'"
			}')
		handleError "$image_response"
		image_url=$(echo $image_response | jq -r '.data[0].url')
		echo -e "\n\033[36mchatgpt \033[0mYour image was created. \n\nLink: ${image_url}\n"

		if [[ "$TERM_PROGRAM" == "iTerm.app" ]]; then
			curl -sS $image_url -o temp_image.png
			imgcat temp_image.png
			rm temp_image.png
		else
			echo "Would you like to open it? (Yes/No)"
			read answer
			if [ "$answer" == "Yes" ] || [ "$answer" == "yes" ] || [ "$answer" == "y" ] || [ "$answer" == "Y" ] || [ "$answer" == "ok" ]; then
				open "${image_url}"
			fi
		fi
	elif [[ "$prompt" == "history" ]]; then
		echo -e "\n$(cat ~/.chatgpt_history)"
	elif [[ "$prompt" == "models" ]]; then
		models_response=$(curl https://api.openai.com/v1/models \
			-sS \
			-H "Authorization: Bearer $OPENAI_KEY")
		handleError "$models_response"
		models_data=$(echo $models_response | jq -r -C '.data[] | {id, owned_by, created}')
		echo -e "\n\033[36mchatgpt \033[0m This is a list of models currently available at OpenAI API:\n ${models_data}"
	elif [[ "$prompt" =~ ^model: ]]; then
		models_response=$(curl https://api.openai.com/v1/models \
			-sS \
			-H "Authorization: Bearer $OPENAI_KEY")
		handleError "$models_response"
		model_data=$(echo $models_response | jq -r -C '.data[] | select(.id=="'"${prompt#*model:}"'")')
		echo -e "\n\033[36mchatgpt \033[0m Complete data for model: ${prompt#*model:}\n ${model_data}"
	else
		# escape quotation marks
		escaped_prompt=$(echo "$prompt" | sed 's/"/\\"/g')
		# escape new lines
		escaped_prompt=${escaped_prompt//$'\n'/' '}

		if [ "$CONTEXT" = true ]; then
			init="You are a Large Language Model created by OpenAI. You are having a chat with a user and must be very helpful, clear and consise in your answers. Use no more than 6 bullet points when you have long answers to give. You were trained on data up until 2021"
			chat_context=$(sed '/session-/h;//!H;$!d;x' ~/.chatgpt_history)
			chat_context=${chat_context//$'\n'/' '}
			chat_context=$(echo "$chat_context" | sed 's/"/\\"/g')

			escaped_prompt="$init $chat_context $escaped_prompt"
		fi

		echo -e $MODEL $escaped_prompt
		# request to OpenAI API
		response=$(curl https://api.openai.com/v1/completions \
			-sS \
			-H 'Content-Type: application/json' \
			-H "Authorization: Bearer $OPENAI_KEY" \
			-d '{
  			"model": "'"$MODEL"'",
  			"prompt": "'"${escaped_prompt}"'",
  			"max_tokens": '$MAX_TOKENS',
  			"temperature": '$TEMPERATURE'
			}')
		echo $response
		handleError "$response"
		response_data=$(echo $response | jq -r '.choices[].text' | sed '1,2d')
		echo -e "\n\033[36mchatgpt \033[0m${response_data}"

		timestamp=$(date +"%d/%m/%Y %H:%M")
		echo -e "$timestamp Q:$prompt \nA:$response_data \n" >>~/.chatgpt_history
	fi
done
