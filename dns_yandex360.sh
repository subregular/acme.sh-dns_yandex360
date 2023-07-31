#!/usr/bin/env sh
# Author: non7top@gmail.com
# 07 Jul 2017
# report bugs at https://github.com/non7top/acme.sh
# 2023-04-05 Adapted for use with Yandex360 by SaGAcious
# 2023-07-24 Thanks to dyadMisha ( https://github.com/dyadMisha ) for the improved support of IDN.

# Values to export:
# export y360_token="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
# export y360_orgID="xxxxxxxxxx"

# Sometimes cloudflare / google doesn't pick new dns records fast enough.
# You can add --dnssleep XX to params as workaround.

########  Public functions #####################

#Usage: dns_myapi_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_yandex360_add() {
  fulldomain="${1}"
  txtvalue="${2}"
  _debug "Calling: dns_yandex360_add() '${fulldomain}' '${txtvalue}'"

  _y360_credentials || return 1

  _y360_get_domain || return 1
  _debug "Found suitable domain: $domain"

  _y360_get_record_ids || return 1
  _debug "Record_ids: $record_ids"

  if [ -n "$record_ids" ]; then
    _info "All existing $subdomain records from $domain will be removed at the very end."
  fi

  data='{"name":"'${subdomain}'","text":"'${txtvalue}'","ttl":"300","type":"TXT"}'
  uri="https://api360.yandex.net/directory/v1/org/$y360_orgID/domains/$(_idn "$domain")/dns"
  result="$(_post "${data}" "${uri}" | _normalizeJson)"
  _debug "Result: $result"

  if ! _contains "$result" '"recordId"'; then
    _err "Can't add $subdomain to $domain."
    return 1
  fi
}

#Usage: dns_myapi_rm   _acme-challenge.www.domain.com
dns_yandex360_rm() {
  if _contains "${1}" 'xn--'; then
    if _exists idn; then
      fulldomain="$(idn -u --quiet "${1}" | tr -d "\r\n")"
    else
      _err "Please install idn to process IDN names."
    fi
  else
    fulldomain="${1}"
  fi
  
  _debug "Calling: dns_yandex360_rm() '${fulldomain}'"

  _y360_credentials || return 1

  _y360_get_domain "$fulldomain" || return 1
  _debug "Found suitable domain: $domain"

  _y360_get_record_ids || return 1
  _debug "Record_ids: $record_ids"

  for record_id in $record_ids; do
    uri="https://api360.yandex.net/directory/v1/org/$y360_orgID/domains/$(_idn "$domain")/dns/$record_id"
    result="$(_post "" "${uri}" "" "DELETE" | _normalizeJson)"
    _debug "Result: $result"

    if ! _contains "$result" '{}'; then
      _info "Can't remove $subdomain from $domain."
    fi
  done
}

####################  Private functions below ##################################

_y360_get_domain() {
  subdomain_start=1
  while true; do
    domain_start=$(_math $subdomain_start + 1)
    domain=$(echo "$fulldomain" | cut -d . -f "$domain_start"-)
    subdomain=$(echo "$fulldomain" | cut -d . -f -"$subdomain_start")

    _debug "Checking domain $domain"
    if [ -z "$domain" ]; then
      _err "Can't find root domain"
      return 1
    fi

    uri="https://api360.yandex.net/directory/v1/org/$y360_orgID/domains/$(_idn "$domain")/dns?page=1&perPage=100"
    result="$(_get "${uri}" | _normalizeJson)"
    _debug "Result: $result"

    if _contains "$result" '"page":1'; then
      return 0
    fi
    subdomain_start=$(_math $subdomain_start + 1)
  done
}

_y360_credentials() {
  if [ -z "${y360_token}" ]; then
    y360_token=""
    _err "You need to export y360_token=xxxxxxxxxxxxxxxxx."
    return 1
  else
    _saveaccountconf y360_token "${y360_token}"
  fi
  if [ -z "${y360_orgID}" ]; then
    y360_orgID=""
    _err "You need to export y360_orgID=xxxxxxxxxxxxxxxxx."
    return 1
  else
    _saveaccountconf y360_orgID "${y360_orgID}"
  fi
  export _H1="Authorization: OAuth $y360_token"
}

_y360_get_record_ids() {
  _debug "Check existing records for $subdomain"

  uri="https://api360.yandex.net/directory/v1/org/$y360_orgID/domains/$(_idn "$domain")/dns?page=1&perPage=100"
  result="$(_get "${uri}" | _normalizeJson)"
  _debug "Result: $result"

  if ! _contains "$result" '"page":1'; then
    return 1
  fi

  record_ids=$(echo "$result" | _egrep_o "{[^{]*\"name\":\"${subdomain}\"[^}]*}" | sed -n -e 's#.*"recordId":\([0-9]*\).*#\1#p')
}
