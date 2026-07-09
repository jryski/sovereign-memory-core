#!/usr/bin/env sh

# Refuse accidental live-database mutations from local validation scripts.
require_safe_database_url() {
  database_url=$1

  if [ -z "$database_url" ]; then
    return 0
  fi

  if [ "${SMC_ALLOW_NONLOCAL_DATABASE:-}" = "1" ]; then
    echo "WARNING: SMC_ALLOW_NONLOCAL_DATABASE=1 permits a non-local database target." >&2
    return 0
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
      case "$query_host" in
        localhost|127.0.0.1|::1|postgres|db|/*|%2[Ff]*) host=$query_host ;;
        *)
          echo "Refusing database target: URI host parameters must name a local socket or approved local host." >&2
          echo "Set SMC_ALLOW_NONLOCAL_DATABASE=1 only after explicitly approving the exact target." >&2
          return 1
          ;;
      esac
      ;;
  esac

  case "$host" in
    localhost|127.0.0.1|::1|postgres|db|/*|%2[Ff]*)
      return 0
      ;;
    '')
      return 0
      ;;
    *)
      echo "Refusing database target: validation scripts require localhost, a local socket, postgres, or db by default." >&2
      echo "Set SMC_ALLOW_NONLOCAL_DATABASE=1 only after explicitly approving the exact target." >&2
      return 1
      ;;
  esac
}
