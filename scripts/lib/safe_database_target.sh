#!/usr/bin/env sh

# Refuse accidental live-database mutations from local validation scripts.
is_safe_database_host() {
  case "$1" in
    localhost|127.0.0.1|::1|postgres|db|/*|%2[Ff]*) return 0 ;;
    *) return 1 ;;
  esac
}

is_safe_database_hostaddr() {
  case "$1" in
    127.0.0.1|::1) return 0 ;;
    *) return 1 ;;
  esac
}

require_safe_database_url() {
  database_url=$1

  if [ -z "$database_url" ]; then
    return 0
  fi

  if [ "${SMC_ALLOW_NONLOCAL_DATABASE:-}" = "1" ]; then
    echo "WARNING: SMC_ALLOW_NONLOCAL_DATABASE=1 permits a non-local database target." >&2
    return 0
  fi

  if [ -n "${PGSERVICE:-}" ] || [ -n "${PGSERVICEFILE:-}" ]; then
    echo "Refusing database target: PGSERVICE and PGSERVICEFILE can hide non-local connection targets." >&2
    echo "Set SMC_ALLOW_NONLOCAL_DATABASE=1 only after explicitly approving the exact target." >&2
    return 1
  fi

  if [ -n "${PGHOST:-}" ] && ! is_safe_database_host "${PGHOST}"; then
    echo "Refusing database target: PGHOST must name a local socket or approved local host." >&2
    echo "Set SMC_ALLOW_NONLOCAL_DATABASE=1 only after explicitly approving the exact target." >&2
    return 1
  fi

  if [ -n "${PGHOSTADDR:-}" ] && ! is_safe_database_hostaddr "${PGHOSTADDR}"; then
    echo "Refusing database target: PGHOSTADDR must be a loopback address." >&2
    echo "Set SMC_ALLOW_NONLOCAL_DATABASE=1 only after explicitly approving the exact target." >&2
    return 1
  fi

  case "$database_url" in
    postgresql://*|postgres://*)
      ;;
    *)
      echo "Refusing database target: validation scripts require a local or disposable PostgreSQL URL by default." >&2
      echo "Set SMC_ALLOW_NONLOCAL_DATABASE=1 only after explicitly approving the exact target." >&2
      return 1
      ;;
  esac

  authority=${database_url#*://}
  authority=${authority%%/*}
  host_port=${authority##*@}

  case "$host_port" in
    \[*\]*) host=${host_port%%]*}; host=${host#\[} ;;
    *) host=${host_port%%:*} ;;
  esac

  case "$database_url" in
    *\?*host=*|*\&host=*)
      query_host=$(printf '%s\n' "$database_url" | sed -n 's/.*[?&]host=\([^&]*\).*/\1/p')
      if ! is_safe_database_host "$query_host"; then
        echo "Refusing database target: URI host parameters must name a local socket or approved local host." >&2
        echo "Set SMC_ALLOW_NONLOCAL_DATABASE=1 only after explicitly approving the exact target." >&2
        return 1
      fi
      host=$query_host
      ;;
  esac

  if [ -z "$host" ] || is_safe_database_host "$host"; then
    return 0
  fi

  echo "Refusing database target: validation scripts require localhost, a local socket, postgres, or db by default." >&2
  echo "Set SMC_ALLOW_NONLOCAL_DATABASE=1 only after explicitly approving the exact target." >&2
  return 1
}
