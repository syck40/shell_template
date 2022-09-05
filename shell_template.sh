#!/usr/bin/env bash

set -Eeo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
echo $script_dir


accounts=("rc3-centech-dev" "rc3-centech-lt" "rc3-centech-prod" "rc3-data-dev" "rc3-devcon-dev" "rc3-devcon-lt" "rc3-devcon-prod" "rc3-devstudio-dev" "rc3-devstudio-lt" "rc3-devstudio-prod" "rc3-esports-dev" "rc3-esports-lt" "rc3-esports-prod" "rc3-infosec" "rc3-liveops-dev" "rc3-liveops-lt" "rc3-liveops-prod" "rc3-lol-lt" "rc3-lol-prod" "rc3-lor-dev" "rc3-lor-lt" "rc3-lor-prod" "rc3-network" "rc3-poolparty-dev" "rc3-poolparty-lt" "rc3-poolparty-prod" "rc3-pp" "rc3-pp-integration" "rc3-pp-lt" "rc3-pp-prod" "rc3-rce-prbuilder" "rc3-rdx-aws-istio" "rc3-rdx-aws-poc" "rc3-rdx-lt" "rc3-rdx-prod" "rc3-rdx-sp-sandbox" "rc3-rdx-sp-test" "rc3-riotdirect-dev" "rc3-riotdirect-lt" "rc3-riotdirect-prod" "rc3-riotpub-dev" "rc3-riotpub-lt" "rc3-riotpub-prod" "rc3-rnd" "rc3-tat-dev" "rc3-torch-dev" "rc3-torch-lt" "rc3-torch-prod" "rc3-val-lt" "rc3-val-prod" "rc3-wr-dev" "rc3-wr-lt" "rc3-wr-poc" "rc3-wr-prod"  "rc3-lol" "rcluster-prod" "rc3-rdx")


setup_colors() {
  if [[ -t 2 ]] && [[ -z "${NO_COLOR-}" ]] && [[ "${TERM-}" != "dumb" ]]; then
    NOFORMAT='\033[0m' RED='\033[0;31m' GREEN='\033[0;32m' ORANGE='\033[0;33m' BLUE='\033[0;34m' PURPLE='\033[0;35m' CYAN='\033[0;36m' YELLOW='\033[1;33m'
  else
    NOFORMAT='' RED='' GREEN='' ORANGE='' BLUE='' PURPLE='' CYAN='' YELLOW=''
  fi
}

msg() {
  echo >&2 -e "${1-}"
}

kc_login () {
	if [ -z $1 ]
	then
		for i in ${accounts[@]}; do
			echo $i
		done
	else
		role="LC-rc3-Gandalf"
		if [[ $2 == "power" ]]; then
			role="GL-Power"
		fi
		acc=$1
		msg "Running kc get ${RED}$account --role=$role ${NOFORMAT}"
		keyconjurer get $1 --role=$role > ~/.kc
    source ~/.kc
	fi
}

list_clusters () {
	if [ -z $1 ]
	then
		region="us-west-2"
	else
		region=$1
	fi
	echo "Running aws eks list-clusters --region $region | jq ."
	aws eks list-clusters --region $region | jq .
}

set_cluster () {
	region="us-west-2"
	if [ -z $1 ]
	then
		echo "Error: missing clustername..."
		exit 1
	else
		cluster_name=$1
	fi
	if [ -z $2 ]
	then
		region="us-west-2"
	else
		region=$2
	fi
	echo "aws eks update-kubeconfig --name $cluster_name --region $region"
	aws eks update-kubeconfig --name $cluster_name --region $region
}

cloud_trail () {
  msg "$1, $2"

	#"AttributeKey": "EventId"|"EventName"|"ReadOnly"|"Username"|"ResourceType"|"ResourceName"|"EventSource"|"AccessKeyId",
	if [ -z $1 ]
	then
		event_name="CreateDBInstance"
	else
		event_name=$1
	fi
	if [ -z $2 ]
	then
		region="us-west-2"
	else
		region=$2
	fi
  msg "RUNNING: ${GREEN}
	aws cloudtrail --region $region lookup-events --start-time $(date -v-30M +%s) --end-time $(date +%s) --query 'Events[].CloudTrailEvent' --lookup-attributes AttributeKey=EventName,AttributeValue=$event_name  --output text | jq .${NOFORMAT}"
	aws cloudtrail --region $region lookup-events --start-time $(date -v-2M +%s) --end-time $(date +%s) --query 'Events[].CloudTrailEvent'  --output text | jq .
}


usage() {
  cat << EOF # remove the space between << and EOF, this is due to web plugin issue
Usage: $(basename "${BASH_SOURCE[0]}") [-l] [args1, args2] [-k] [arg1] [-s] [args1,args2] [-t] 

RDX SP scripts.

Available options:

-l, --login       kc_login account role, [-l rc3-rdx] or [-l] to list all or [-l rc3-rdx power] to login as power to rc3-rdx
-k, --k8clusters  list_clusters region, -k us-west-2
-s, --k8set       set_cluster clustername region, -s aws_rc3-rdx_usw2_edge-ci
-t, --cloudtrail  aws cloudtrail
-d, --dcos        dcos [datacenter-name], ams1

-h, --help      Print this help and exit
-v, --verbose   Print script debug info
EOF
  exit
}

cleanup() {
  trap - SIGINT SIGTERM ERR EXIT
  # script cleanup here
}

die() {
  local msg=$1
  local code=${2-1} # default exit status 1
  msg "$msg"
  exit "$code"
}

dcos_open () {
	datacenter=$1
	lpass_id=$(lpass ls | grep dcos_admin_pass | grep ${datacenter} | cut -d " " -f 3 | sed 's/]//')
	if [ -z ${lpass_id} ]
	then
		echo "no results for datacenter '${datacenter}'"
		return
	fi
	echo "Lastpass ID: ${lpass_id}"
	dcos_url=$(lpass show --url ${lpass_id})
	echo "Opening dcos url in chrome"
	echo ${dcos_url}
	dcos_user=$(lpass show --username ${lpass_id})
	dcos_pass=$(lpass show --password  ${lpass_id})
	echo "Username: ${dcos_user}"
	echo "copying password to clipboard"
	echo ${dcos_pass} | pbcopy
	open -a "Google Chrome" ${dcos_url}
}

parse_params() {
  # default values of variables set from params
  flag=0
  param=''

  while :; do
    case "${1-}" in
		-l | --login)
			account="$2"
			role="$3"
			kc_login $account $role
			shift
			shift
			shift
			;;
		-k | --k8clusters)
			region="$2"
			list_clusters $region
			shift
			shift
			;;
		-s | --k8set)
			clustername="$2"
			region="$3"
			set_cluster $clustername $region
			shift
			shift
			shift
			;;
		-t | --cloudtrail)
			eventname="$2"
			region="$3"
      msg "SAMPLE:	aws cloudtrail --region $region lookup-events --start-time $(date -v-15d +%s) --end-time $(date +%s) --query 'Events[].CloudTrailEvent' --lookup-attributes AttributeKey=EventName,AttributeValue=$event_name  --output text | jq ."
      msg 'SAMPLE: "AttributeKey": "EventId"|"EventName"|"ReadOnly"|"Username"|"ResourceType"|"ResourceName"|"EventSource"|"AccessKeyId"'
      shift
      shift
			cloud_trail $eventname $region
			;;
		-d | --dcos)
			dc="$2"
      shift
			dcos_open $dc
			;;
    -h | --help) usage ;;
    -v | --verbose) set -x ;;
    --no-color) NO_COLOR=1 ;;
    -f | --flag) flag=1 ;; # example flag
    -p | --param) # example named parameter
      param="${2-}"
      shift
      ;;
    -?*) die "Unknown option: $1" ;;
    *) break ;;
    esac
    shift
  done

  args=("$@")

  # check required params and arguments
  [[ -z "${param-}" ]] && usage
  [[ ${#args[@]} -eq 0 ]] && die "Missing script arguments"

  return 0
}

setup_colors
parse_params "$@"

# script logic here

msg "${RED}Read parameters:${NOFORMAT}"
msg "- flag: ${flag}"
msg "- param: ${param}"
msg "- arguments: ${args[*]-}"


#keyconjurer get rc3-riotpub-dev --role=LC-rc3-Gandalf > ~/.kc
#keyconjurer get rc3-riotpub-prod --role=LC-rc3-Gandalf > ~/.kc
#keyconjurer get rc3-centech-prod --role=LC-rc3-Gandalf > ~/.kc
#keyconjurer get rc3-centech-dev --role=LC-rc3-Gandalf > ~/.kc
#keyconjurer get rc3-rdx --role=GL-Power > ~/.kc
#keyconjurer get rc3-rdx-prod --role=LC-rc3-Gandalf > ~/.kc
#keyconjurer get rc3-pp --role=LC-rc3-Gandalf > ~/.kc
#keyconjurer get rc3-pp-integration --role=LC-rc3-Gandalf > ~/.kc
#keyconjurer get rc3-pp-integration --role=GL-Power > ~/.kc
#keyconjurer get rc3-lol --role=LC-rc3-Gandalf > ~/.kc
#keyconjurer get rcluster-prod --role=GL-Power > ~/.kc

#aws eks list-clusters --region us-west-2 | jq .
#aws eks update-kubeconfig --name aws_rc3-rdx-prod_usw2_prod --region us-west-2
