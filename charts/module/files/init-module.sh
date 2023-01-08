#!/bin/bash

cd `dirname $0`

set -o pipefail -o noclobber

# keep for backward compatibility
if [ "$MODULE_URL" != "" ]; then
  SERVICE_URL=$MODULE_URL
fi

module_descriptor_file='/tmp/module-descriptor.json'

superusertoken=""

okapi_ready_check() {
  echo -ne "-- Checking if okapi is ready..."
  local returncode=`curl -s -w "%{http_code}" \
    -H "X-Okapi-Token: ${superusertoken}" \
    -o /dev/null \
    ${OKAPI_URL}/_/discovery/modules`
  case "${returncode}" in
    200|201)
      echo "done"
      return 0
    ;;
  esac
  echo "ERROR, returncode ${returncode}"
  return 1
}

# tests against the configured okapi-url whether the module is already introduced
is_module_introduced() {
  echo -ne "-- testing whether module ${SERVICE_ID} is already introduced to ${OKAPI_URL} ...";
  result=`curl \
    -s \
    -w "%{http_code}" \
    -H "X-Okapi-Token: ${superusertoken}" \
    -o /dev/null \
    "${OKAPI_URL}/_/proxy/modules/${SERVICE_ID}"`;

    case "${result##*|}" in
        200)
                echo "already introduced."
                return 0
		;;
	404)
                echo "not found."
                return 1
                ;;
	*)
                echo "${result##*|} (${result%|*})"
                return 127
                ;;
	esac
}

# fetch the module descriptor from registry
fetch_module_descriptor() {
  echo -ne "-- Fetching module descriptor of ${SERVICE_ID}..."

  local TRY_COUNT=3
  while [ true ]; do
    if [ $TRY_COUNT = 0 ]; then break; fi
    result=`curl \
      -s \
      -w '|%{http_code}' -X GET \
      -H "X-Okapi-Token: ${superusertoken}" \
      -H "Content-type: application/json" \
      "${FOLIO_REGISTRY}/_/proxy/modules/${MODULE}-${TAG}" \
      -o ${module_descriptor_file} 2>&1`

    case "${result##*|}" in
      200|201)
        echo "done"
        return 0
        ;;
    esac

    let TRY_COUNT=$TRY_COUNT-1
    sleep 1
  done

  echo "${result##*|} ("${result%|*}")"
  return 127
}

# introduces the module in okapi
introduce_module() {
  echo -ne "-- introducing module ${SERVICE_ID} to ${OKAPI_URL} ..."

  if [ ! -e "${module_descriptor_file}" ]; then
    echo "error. module_descriptor does not exist.";
    return 0;
  fi;

  local TRY_COUNT=3
  while [ true ]; do
    if [ $TRY_COUNT = 0 ]; then break; fi
    result=`curl \
      -s \
      -w '|%{http_code}' -X POST \
      -H "X-Okapi-Token: ${superusertoken}" \
      -H "Content-type: application/json" \
      "${OKAPI_URL}/_/proxy/modules" \
      -d @${module_descriptor_file} 2>&1`

    case "${result##*|}" in
      200|201)
        echo "done"
        return 0
        ;;
    esac

    let TRY_COUNT=$TRY_COUNT-1
    sleep 1
  done

  echo "${result##*|} ("${result%|*}")"
  return 127
}



is_service_registered() {
  echo -ne "-- testing whether module ${SERVICE_ID} is already enabled in ${OKAPI_URL} ...";
  result=`curl \
    -s \
    -w "%{http_code}" \
    -H "X-Okapi-Token: ${superusertoken}" \
    -o /dev/null \
    "${OKAPI_URL}/_/discovery/modules/${SERVICE_ID}"`;

	case "${result##*|}" in
		200)
      echo "already enabled."
			return 0
			;;
		404)
      echo "not found."
      return 1
      ;;
		*)
      echo "${result##*|} (${result%|*})"
      return 127
      ;;
	esac
}

deregister_service() {
  echo -ne "-- removing module ${SERVICE_ID} from ${OKAPI_URL} ...";
  result=`curl \
    -s \
    -X DELETE \
    -w "%{http_code}" \
    -H "X-Okapi-Token: ${superusertoken}" \
    -o /dev/null \
    "${OKAPI_URL}/_/discovery/modules/${SERVICE_ID}"`;

	case "${result##*|}" in
		204)
      echo "done."
			return 0
			;;
		*)
      echo "${result##*|} (${result%|*})"
      return 127
      ;;
	esac
}


# enables the module in okapi
register_service() {
  echo -ne "-- enabling module ${SERVICE_ID} to ${OKAPI_URL} ..."

  local enable_descriptor="{\"srvcId\":\"${SERVICE_ID}\",\"instId\":\"${INSTALL_ID}\",\"url\":\"${SERVICE_URL}\"}"

  local TRY_COUNT=3
  while [ true ]; do
    if [ $TRY_COUNT = 0 ]; then break; fi

    result=`echo $enable_descriptor | curl \
      -s \
      -w "|%{http_code}" -X POST \
      -H 'Content-type: application/json' \
      -H "X-Okapi-Token: ${superusertoken}" \
      "$OKAPI_URL/_/discovery/modules" \
      -d @- 2>&1`

    case "${result##*|}" in
      200|201)
        echo "done"
        return 0
        ;;
    esac

    sleep 1
    let TRY_COUNT=$TRY_COUNT-1
  done

  echo "${result##*|} ("${result%|*}")"
  #timeout hit
  return 127
}

deploy_module() {
  if [ "${SELF_INTRODUCE}" == "false" ]; then
    echo "=== okapi-setup skipped because of SELF_INTRODUCE=false ==="
    return 0
  fi

  echo "=== performing okapi-setup ==="
  is_module_introduced || ( fetch_module_descriptor && introduce_module )

  return $?
}

enable_service() {
  if [ "${REGISTER_SERVICE}" == "false" ]; then
    echo "=== okapi-setup skipped registering service because of REGISTER_SERVICE=false ==="
    return 0
  fi

  is_service_registered && (deregister_service || return $?)
  register_service

  return $?
}


get_superuser_token() {
        echo -ne "-- Getting superuser token..."
        local payload
        read -r -d '' payload <<EOF
{
  "username": "superuser",
  "password": "${SUPERUSER_PASSWORD}"
}
EOF
        result=`echo "${payload}" | curl \
                -s \
                -D - \
                -w '|%{http_code}' \
                -X POST  \
                -H "Content-type: application/json" \
                -H "X-Okapi-Tenant: supertenant" \
                "${OKAPI_URL}/authn/login" \
                -d@-`

        case "${result##*|}" in
                200|201)
                        token=`echo "${result%|*}" | grep -i x-okapi-token`
                        superusertoken=`expr "$token" : '[^:]\+:\s*\(.\+\)$'`
                        echo "done."
                        return 0
                        ;;
        esac

        echo "failed."
        echo "${result##*|} ("${result%|*}")"
        echo "okapi still unsecured?"
        echo "continuing with empty superusertoken..."
        return 17
}



# main entry
main() {
  get_superuser_token
  okapi_ready_check \
  && deploy_module \
  && enable_service

  return $?

}

main
