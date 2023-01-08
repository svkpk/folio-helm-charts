#!/usr/bin/env /bin/bash

set -o pipefail -o noclobber 

tenant_id=""
name=""
description=""
modules="okapi"
frontend_modules=""
authtoken=""
okapi_token=""
permission_id=""
permissions=""
module_descriptor=""
loadSample=false
loadReference=false

superusertoken=""

parse_cmdline_parameters() {
  ! getopt --test >/dev/null
  if [[ ${PIPESTATUS[0]} -ne 4 ]]; then
    echo "I’m sorry, `getopt --test` failed in this environment."
    exit 1
  fi

  OPTIONS=
  LONGOPTS=install-backend-module:,install-frontend-module:,name:,id:,description:,debug,loadSample,loadReference
  ! PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTS --name "$0" -- "$@")

  if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    # e.g. return value is 1
    #  then getopt has complained about wrong arguments to stdout
    exit 2
  fi
  # read getopt’s output this way to handle the quoting right:
  eval set -- "$PARSED"

  while true; do
    case "$1" in
      --install-backend-module)
        modules="${modules} $2"
        shift 2
        ;;
      --install-frontend-module)
        frontend_modules="${frontend_modules} $2"
        modules="${modules} $2"
        shift 2
        ;;
      --id)
        tenant_id="$2"
        shift 2
        ;;
      --name)
        tenant_name="$2"
        shift 2
        ;;
      --description)
        description="$2"
        shift 2
        ;;
      --debug)
        debug=1
        shift
        ;;
      --loadSample)
        loadReference=true
        loadSample=true
        shift
        ;;
      --loadReference)
        loadReference=true
        shift
        ;;
      --)
        shift
        break
        ;;
      *)
        echo "Argument not allowed"
        echo $1
        exit 3
        ;;
    esac
  done
}

debug() {
  if [ "$debug" != "1" ];then
    return 0
  fi

  echo -ne "\n\n---debug---\n$1: $2\n---debugend---\n\n"
  return 0
}

# fetches the module-descriptor from the public folio module-registry defined by env var FOLIO_REGISTRY
fetch_module_descriptor() {
  local module=$1
  echo -ne "fetching module-descriptor from ${FOLIO_REGISTRY} for ${module} ..."

  result=`curl \
    -w '|%{http_code}' \
    -H "X-Okapi-Tenant:supertenant" \
    -H "X-Okapi-Token: ${superusertoken}" \
    -s \
    "${FOLIO_REGISTRY}/_/proxy/modules/${module}" 2>&1`

  debug "fetch_module_descriptor" "${FOLIO_REGISTRY}/_/proxy/modules/${module}"
  case "${result##*|}" in
    200|201)
      module_descriptor="${result%|*}"
      echo "done"
      return 0
      ;;
    *)
      echo "${result##*|} (${result%|*})"
      return 4
      ;;
  esac
}

wait_for_okapi() {
  echo -ne "Waiting for okapi at ${OKAPI_URL} to become ready ..."
  local $TRY_COUNT=3
  while [ true ]; do
    if [ $TRY_COUNT = 0 ]; then break; fi

    result=`curl \
      -s \
      -w "%{http_code}" \
      -H "X-Okapi-Tenant:supertenant" \
      -H "X-Okapi-Token: ${superusertoken}" \
      -o /dev/null \
      ${OKAPI_URL}/_/discovery/modules`

    case "${result}" in
      200|201)
        echo "done"
        return 0
        ;;
    esac

    let TRY_COUNT=$TRY_COUNT-1
    sleep 1
  done

  echo "timed out waiting for okapi at ${OKAPI_URL}"
  return 1
}

wait_for_backend_modules() {
  for module in $@; do
    wait_for_backend_module $module || return $?
  done

  return 0
}

wait_for_backend_module() {
  echo -ne "Waiting for backend-module ${module} ..."
  local $TRY_COUNT=3 
  while [ true ]; do
    if [ $TRY_COUNT = 0 ]; then break; fi
      result=`curl \
        -s \
        -w "%{http_code}" \
        -H "X-Okapi-Tenant:supertenant" \
        -H "X-Okapi-Token: ${superusertoken}" \
        -o /dev/null \
        "${OKAPI_URL}/_/discovery/modules/${module}"`;
  case "${result}" in
    200|201)
      echo "done"
      return 0
      ;;
    *)
      echo "${result}"
      return 2
      ;;
    esac

    let TRY_COUNT=$TRY_COUNT-1
    sleep 1
  done

  echo "timed out waiting for backend-module at ${module}"
  return 3
}

# tests against the configured okapi-url whether the module is already registered
is_module_registered() {
  local module=$1
  echo -ne "testing whether module ${module} is already registered to ${OKAPI_URL} ...";
  result=`curl \
    -s \
    -w "%{http_code}" \
    -H "X-Okapi-Tenant:supertenant" \
    -H "X-Okapi-Token: ${superusertoken}" \
    -o /dev/null \
    "${OKAPI_URL}/_/proxy/modules/${module}"`;

  case "${result##*|}" in
    200)
      echo "already registered."
      return 0
      ;;
    404)
      echo "not found."
      return 2
      ;;
    *)
      echo "${result##*|} (${result%|*})"
      return 3
      ;;
  esac
}

# registers the module in okapi
register_module() {
  local module=$1
  echo -ne "registering module ${module} to ${OKAPI_URL} ..."

  if [ "$module_descriptor" == "" ]; then
    echo "error. module_descriptor empty";
    return 0;
  fi;
  local TRY_COUNT=3
  while [ true ]; do
    if [ $TRY_COUNT = 0 ]; then break; fi
    result=`echo $module_descriptor | curl \
      -s \
      -w '|%{http_code}' -X POST \
      -H "Content-type: application/json" \
      -H "X-Okapi-Tenant:supertenant" \
      -H "X-Okapi-Token: ${superusertoken}" \
      "${OKAPI_URL}/_/proxy/modules" \
      -d @- 2>&1`

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
  return 5
}

tenant_exists() {
  echo -ne "Checking whether tenant ${tenant_id} already exists ...";

  result=`curl \
    -w '|%{http_code}' \
    -s \
    -H 'Content-type: application/json' \
    -H "X-Okapi-Tenant:supertenant" \
    -H "X-Okapi-Token: ${superusertoken}" \
    $OKAPI_URL/_/proxy/tenants/${tenant_id}`

  case "${result##*|}" in
    200|201)
      echo "yes. Skipping creating tenant"
      return 0
      ;;
    404)
      echo "no"
      return 4
      ;;
    *)
      echo "${result##*|} ("${result%|*}")"
      return 5
  esac
}

create_tenant() {
  echo -ne "Creating tenant ..."

  local payload

  read -r -d '' payload <<EOF
{
  "id": "${tenant_id}",
  "name": "${tenant_name}",
  "description": "${description}"
}
EOF

  result=`echo $payload | curl \
    -s \
    -w '|%{http_code}' \
    -X POST \
    -H 'Content-type: application/json' \
    -H "X-Okapi-Tenant:supertenant" \
    -H "X-Okapi-Token: ${superusertoken}" \
    "${OKAPI_URL}/_/proxy/tenants" -d @-  2>&1`

  case "${result##*|}" in
    200|201)
      echo "done"
      return 0
      ;;
    *)
      echo "${result##*|} ("${result%|*}")"
      return 6
      ;;
  esac
}

install_modules() {
  echo -ne "Installing modules for tenant ..."

  local payload
  local module

  for module in $@; do
    read -r -d '' part <<EOF
{
  "id": "${module}",
  "action": "enable"
}
EOF

  payload="${payload}${part},"
  done

  payload="[${payload%%,}]"

  debug "install_modules()" "$payload"

  local TRY_COUNT=3
  while true; do
    if [ $TRY_COUNT = 0 ]; then break; fi
    result=`echo "$payload" | curl \
      -s \
      -X POST \
      -w "|%{http_code}" \
      -H 'Content-type: application/json' \
      -H "X-Okapi-Tenant:supertenant" \
      -H "X-Okapi-Token: ${superusertoken}" \
      "${OKAPI_URL}/_/proxy/tenants/${tenant_id}/install?tenantParameters=loadSample=${loadSample},loadReference=${loadReference}" \
      -d @- 2>&1`

    case "${result##*|}" in
      200|201)
        echo "done."
        return 0
        ;;
    esac

    let TRY_COUNT=$TRY_COUNT-1
    sleep 1
  done

  echo "${result##*|} ("${result%|*}")"
  return 12
}

find_module_authtoken() {
  echo -ne "Find module authtoken for tenant..."

  result=`curl \
    -s \
    -w "|%{http_code}" \
    -H 'Content-type: application/json' \
    -H "X-Okapi-Tenant:supertenant" \
    -H "X-Okapi-Token: ${superusertoken}" \
    "${OKAPI_URL}/_/proxy/tenants/${tenant_id}/interfaces/authtoken" 2>&1`

  case "${result##*|}" in
    200|201)
      authtoken=`echo "${result%|*}" | grep id | awk -F \" '{ print $4; }'`
      echo "done."
      return 0
      ;;
  esac

  echo "${result##*|} ("${result%|*}")"
  return 11
}

disable_module_for_tenant() {
  local module=$1
  echo -ne "Disabling module ${module} for tenant..."
  local TRY_COUNT=3
  while [ true ]; do
    if [ $TRY_COUNT = 0 ]; then break; fi
    result=`echo "[{\"id\" : \"${module}\", \"action\": \"disable\"}]" | curl \
      -s \
      -X POST \
      -w "|%{http_code}" \
      -H 'Content-type: application/json' \
      -H "X-Okapi-Tenant:supertenant" \
      -H "X-Okapi-Token: ${superusertoken}" \
      "${OKAPI_URL}/_/proxy/tenants/${tenant_id}/install" \
      -d @- 2>&1`

    case "${result##*|}" in
      200|201)
        echo "done."
        return 0
        ;;
    esac

    let TRY_COUNT=$TRY_COUNT-1
    sleep 1
  done

  echo "${result##*|} ("${result%|*}")"
  return 12
}

create_admin() {
  echo -ne "Creating ${ADMIN_USERNAME} account for tenant ..."

  local payload

  read -r -d '' payload <<EOF
{
  "id": "${ADMIN_ID}",
  "username": "${ADMIN_USERNAME}",
  "active": "true",
  "personal": {
    "lastName": "Administrator"
  }
}
EOF

  result=`echo "$payload" | curl \
    -s \
    -w '|%{http_code}' \
    -X POST \
    -H "Content-type: application/json" \
    -H "X-Okapi-Tenant:${tenant_id}" \
    "${OKAPI_URL}/users" \
    -d @- 2>&1`

  case "${result##*|}" in
    200|201)
      echo "done."
      return 0
      ;;
    422)
      echo "already exists. Deleting and recreating ..."
      delete_and_recreate_admin
      return $?
      ;;
  esac

  echo "${result##*|} ("${result%|*}")"
  return 13
}


delete_and_recreate_admin() {
  echo -en "Deleting ${ADMIN_USERNAME} account for tenant ... "

  result=`curl -s \
    -X DELETE \
    -w '|%{http_code}' \
    -H "Content-type: application/json" \
    -H "X-Okapi-Tenant:${tenant_id}" \
    "${OKAPI_URL}/users/${ADMIN_ID}" \
    2>&1`

  case "${result##*|}" in
    204)
      echo "done. Trying create again ..."
      create_admin
      return $? 
      ;;
  esac

  echo "${result##*|} ("${result%|*}")"
  return 13
}


create_admin_credentials() {
  echo -ne "Creating ${ADMIN_USERNAME} credentials for tenant ..."

  local payload

  read -r -d '' payload <<EOF
{
  "userId": "${ADMIN_ID}",
  "password": "${ADMIN_PASSWORD}"
}
EOF

  result=`echo "$payload" | curl \
    -s \
    -w '|%{http_code}' \
    -X POST \
    -H "Content-type: application/json" \
    -H "X-Okapi-Tenant:${tenant_id}" \
    "${OKAPI_URL}/authn/credentials" \
    -d @- 2>&1`

  case "${result##*|}" in
    200|201)
      echo "done."
      return 0
      ;;
    422)
      echo "already exists."
      return 0
      ;;
  esac

  echo "${result##*|} ("${result%|*}")"
  return 13
}

create_admin_permission() {
  local permission=$1
  echo -ne "Creating permission ${permission} for ${ADMIN_USERNAME} ..."

  local payload

  read -r -d '' payload <<EOF
{
  "userId": "${ADMIN_ID}",
  "permissions": [ "${permission}" ]
}
EOF

  result=`echo "${payload}" | curl \
    -s \
    -w '|%{http_code}' \
    -X POST \
    -H "Content-type: application/json" \
    -H "X-Okapi-Tenant:${tenant_id}" \
    "${OKAPI_URL}/perms/users" \
    -d @- 2>&1`

  case "${result##*|}" in
    200|201)
      echo "done."
      return 0
      ;;
    400)
      echo "${result##*|} ("${result%|*}")"
      echo "duplicate key?, trying to continue..."
      return 0
      ;;
    422)
      echo "already exists."
      return 0
      ;;
  esac

  echo "${result##*|} ("${result%|*}")"
  return 14
}

login() {
  echo -ne "Logging ${ADMIN_USERNAME} in for tenant ..."

  local payload

  read -r -d '' payload <<EOF
{
  "username": "${ADMIN_USERNAME}",
  "password": "${ADMIN_PASSWORD}"
}
EOF

  result=`echo "$payload" | curl \
    -s \
    -w '|%{http_code}' \
    -D - \
    -X POST \
    -H "Content-type: application/json" \
    -H "X-Okapi-Tenant:${tenant_id}" \
    "${OKAPI_URL}/bl-users/login" \
    -d @- 2>&1`

  case "${result##*|}" in
    200|201)
      echo "done."
      permission_id=`echo "${result%|*}" | grep "permissions" -A 1 | grep id | awk -F \" '{ print $4; }'`
      token=`echo "${result%|*}" | grep -i x-okapi-token`
      okapi_token=`expr "$token" : '[^:]\+:\s*\(.\+\)$'`
      return 0
      ;;
  esac

  echo "${result##*|} ("${result%|*}")"
  return 15
}

get_permissions() {
  echo -ne "Retreiving permissions for tenant ..."

  result=`curl \
    -s \
    -w '|%{http_code}' \
    -X GET \
    -H "Content-type: application/json" \
    -H "X-Okapi-Tenant: ${tenant_id}" \
    -H "X-Okapi-Token: ${okapi_token}" \
    "${OKAPI_URL}/perms/permissions?query=childOf%3D%3D%5B%5D&length=1000" 2>&1`

  case "${result##*|}" in
    200|201)
      echo "done."
      permissions="$permissions "`echo "${result%|*}" | grep '"permissionName" :' | awk -F \" '{ print $4; }' | xargs echo -ne`
      debug get_permissions "$permissions"
      return 0
      ;;
  esac

  echo "${result##*|} ("${result%|*}")"
  return 16
}

assign_permission() {
  local permission=$1

  echo -ne "Assigning permission ${permission} to ${ADMIN_USERNAME} ..."

  local payload

  read -r -d '' payload <<EOF
{
  "permissionName": "${permission}"
}
EOF

  result=`echo "$payload" | curl \
    -s \
    -w '|%{http_code}' \
    -X POST \
    -H "Content-type: application/json" \
    -H "X-Okapi-Tenant: ${tenant_id}" \
    -H "X-Okapi-Token: ${okapi_token}" \
    "${OKAPI_URL}/perms/users/${permission_id}/permissions" \
    -d @- 2>&1`

  case "${result##*|}" in
    200|201)
      echo "done."
      return 0
      ;;
    *)
      echo "${result##*|} ("${result%|*}")"
      return 0
      ;;
  esac
}

register_frontend_modules() {
  for i in $@; do
    is_module_registered $i \
    || (fetch_module_descriptor $i && register_module $i) || return $?
  done;
}

assign_permissions() {
  for i in $@; do
    assign_permission $i || return $?
  done;
}

get_superuser_token() {
  echo -ne "Getting superuser token..."
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

  echo "${result##*|} ("${result%|*}")"
  return 17
}


main() {
  parse_cmdline_parameters $@ \
  && echo "Starting to register tenant ${tenant_id} with okapi at ${OKAPI_URL}..." \
  && get_superuser_token \
  && register_frontend_modules $frontend_modules \
  && (tenant_exists || create_tenant) \
  && wait_for_backend_modules $backend_modules && install_modules $modules \
  && find_module_authtoken \
  && disable_module_for_tenant $authtoken \
  && create_admin \
  && create_admin_credentials \
  && create_admin_permission "perms.all" \
  && install_modules $modules \
  && login \
  && get_permissions \
  && assign_permissions $permissions

  return $?
}

main "$@"
