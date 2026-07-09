#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="gitlab"
APP_VERSION="0.1.0"
WORKDIR="/tmp/${APP_NAME}-installer"
PAYLOAD_ARCHIVE="${WORKDIR}/payload.tar.gz"
MANIFEST_DIR="${WORKDIR}/manifests"
IMAGE_DIR="${WORKDIR}/images"
IMAGE_INDEX="${IMAGE_DIR}/image-index.tsv"

ACTION="help"
RELEASE_NAME="gitlab"
NAMESPACE="gitlab-system"
HOSTNAME="gitlab.aisphere.local"
EXTERNAL_URL=""
TIMEZONE="Asia/Shanghai"
ROOT_PASSWORD="GitLab@Passw0rd"
STORAGE_CLASS="nfs"
CONFIG_STORAGE_SIZE="5Gi"
LOGS_STORAGE_SIZE="20Gi"
DATA_STORAGE_SIZE="100Gi"
RESOURCE_PROFILE="mid"
CPU_REQUEST=""
CPU_LIMIT=""
MEMORY_REQUEST=""
MEMORY_LIMIT=""
PUMA_WORKERS=""
SIDEKIQ_CONCURRENCY=""
ENABLE_EMBEDDED_PROMETHEUS="false"
IMAGE_PULL_POLICY="IfNotPresent"
WAIT_TIMEOUT="30m"
REGISTRY_REPO="sealos.hub:5000/kube4"
REGISTRY_REPO_EXPLICIT="false"
REGISTRY_USER="admin"
REGISTRY_PASS="passw0rd"
SKIP_IMAGE_PREPARE="false"
DELETE_PVC="false"
AUTO_YES="false"

ENABLE_GATEWAY="true"
REQUIRE_GATEWAY="false"
GATEWAY_NAME="aisphere-gateway"
GATEWAY_NAMESPACE="aisphere"
GATEWAY_HTTP_SECTION="https"
ENABLE_SSH_ROUTE="false"
GATEWAY_SSH_SECTION="ssh"
SSH_EXTERNAL_PORT="22"

ENABLE_OIDC="false"
OIDC_PROVIDER_LABEL="Casdoor"
OIDC_ISSUER="https://casdoor.aisphere.local"
OIDC_CLIENT_ID=""
OIDC_CLIENT_SECRET=""
OIDC_REDIRECT_URI=""
OIDC_SCOPE="openid profile email"
OIDC_UID_FIELD="sub"
OIDC_AUTO_SIGN_IN="false"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log() { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
die() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
section() { echo; echo -e "${BLUE}${BOLD}============================================================${NC}"; echo -e "${BLUE}${BOLD}$*${NC}"; echo -e "${BLUE}${BOLD}============================================================${NC}"; }
program_name() { basename "$0"; }

usage() {
  local cmd="./$(program_name)"
  cat <<EOF_USAGE
Usage:
  ${cmd} <install|uninstall|status|help> [options]
  ${cmd} -h|--help

Actions:
  install       Prepare images and install or upgrade GitLab
  uninstall     Remove Kubernetes objects. PVCs are preserved unless --delete-pvc is set
  status        Show StatefulSet, Pod, Service, PVC and Gateway API status
  help          Show this message

Core options:
  -n, --namespace <ns>                 Namespace, default: ${NAMESPACE}
  --release-name <name>                Resource name prefix, default: ${RELEASE_NAME}
  --hostname <host>                    Public GitLab hostname, default: ${HOSTNAME}
  --external-url <url>                 Public URL, default: https://<hostname>
  --timezone <tz>                      GitLab timezone, default: ${TIMEZONE}
  --root-password <password>           Initial root password, default: ${ROOT_PASSWORD}
  --storage-class <name>               StorageClass for PVCs, default: ${STORAGE_CLASS}
  --config-storage-size <size>         /etc/gitlab PVC size, default: ${CONFIG_STORAGE_SIZE}
  --logs-storage-size <size>           /var/log/gitlab PVC size, default: ${LOGS_STORAGE_SIZE}
  --data-storage-size <size>           /var/opt/gitlab PVC size, default: ${DATA_STORAGE_SIZE}
  --resource-profile <low|mid|high>    Resource profile, default: ${RESOURCE_PROFILE}

Image and rollout:
  --registry <repo-prefix>             Target image repo prefix, default: ${REGISTRY_REPO}
  --registry-user <user>               Registry username, default: ${REGISTRY_USER}
  --registry-password <password>       Registry password, default: <hidden>
  --image-pull-policy <policy>         Always|IfNotPresent|Never, default: ${IMAGE_PULL_POLICY}
  --skip-image-prepare                 Reuse images already pushed to the target registry
  --wait-timeout <duration>            Rollout wait timeout, default: ${WAIT_TIMEOUT}

Envoy Gateway API exposure:
  --enable-gateway                     Create HTTPRoute, default: enabled
  --disable-gateway                    Do not create HTTPRoute
  --require-gateway                    Fail install if Gateway API HTTPRoute CRD is missing
  --gateway-name <name>                Gateway name, default: ${GATEWAY_NAME}
  --gateway-namespace <ns>             Gateway namespace, default: ${GATEWAY_NAMESPACE}
  --gateway-http-section <section>     Gateway HTTP/HTTPS listener sectionName, default: ${GATEWAY_HTTP_SECTION}
  --enable-ssh-route                   Also create TCPRoute for SSH clone/push
  --disable-ssh-route                  Do not create TCPRoute, default
  --gateway-ssh-section <section>      Gateway TCP listener sectionName, default: ${GATEWAY_SSH_SECTION}
  --ssh-external-port <port>           External SSH port shown by GitLab, default: ${SSH_EXTERNAL_PORT}

Casdoor OIDC:
  --enable-oidc                        Enable GitLab OmniAuth OpenID Connect provider
  --disable-oidc                       Disable OIDC, default
  --oidc-label <label>                 Login button label, default: ${OIDC_PROVIDER_LABEL}
  --oidc-issuer <url>                  Casdoor issuer URL, default: ${OIDC_ISSUER}
  --oidc-client-id <id>                Casdoor application client id
  --oidc-client-secret <secret>        Casdoor application client secret
  --oidc-redirect-uri <url>            Default: <external-url>/users/auth/openid_connect/callback
  --oidc-scope <scope>                 Space-separated scope string, default: ${OIDC_SCOPE}
  --oidc-uid-field <claim>             Stable user id claim, default: ${OIDC_UID_FIELD}
  --oidc-auto-sign-in                  Redirect login page directly to Casdoor

Other:
  --delete-pvc                         With uninstall, also delete PVCs created by this release
  -y, --yes                            Skip confirmation
  -h, --help                           Show help

Examples:
  ${cmd} install --storage-class nfs --hostname gitlab.aisphere.local -y
  ${cmd} install --registry harbor.example.com/kube4 --skip-image-prepare -y
  ${cmd} install --enable-oidc --oidc-client-id gitlab --oidc-client-secret 'secret' -y
  ${cmd} status -n gitlab-system
  ${cmd} uninstall -n gitlab-system -y
EOF_USAGE
}

cleanup() { rm -rf "${WORKDIR}"; }
trap cleanup EXIT

parse_args() {
  if [[ $# -eq 0 ]]; then ACTION="help"; return; fi
  while [[ $# -gt 0 ]]; do
    case "$1" in
      install|uninstall|status|help) ACTION="$1"; shift ;;
      -n|--namespace) [[ $# -ge 2 ]] || die "Missing value for $1"; NAMESPACE="$2"; shift 2 ;;
      --release-name) [[ $# -ge 2 ]] || die "Missing value for $1"; RELEASE_NAME="$2"; shift 2 ;;
      --hostname) [[ $# -ge 2 ]] || die "Missing value for $1"; HOSTNAME="$2"; shift 2 ;;
      --external-url) [[ $# -ge 2 ]] || die "Missing value for $1"; EXTERNAL_URL="$2"; shift 2 ;;
      --timezone) [[ $# -ge 2 ]] || die "Missing value for $1"; TIMEZONE="$2"; shift 2 ;;
      --root-password) [[ $# -ge 2 ]] || die "Missing value for $1"; ROOT_PASSWORD="$2"; shift 2 ;;
      --storage-class) [[ $# -ge 2 ]] || die "Missing value for $1"; STORAGE_CLASS="$2"; shift 2 ;;
      --config-storage-size) [[ $# -ge 2 ]] || die "Missing value for $1"; CONFIG_STORAGE_SIZE="$2"; shift 2 ;;
      --logs-storage-size) [[ $# -ge 2 ]] || die "Missing value for $1"; LOGS_STORAGE_SIZE="$2"; shift 2 ;;
      --data-storage-size) [[ $# -ge 2 ]] || die "Missing value for $1"; DATA_STORAGE_SIZE="$2"; shift 2 ;;
      --resource-profile) [[ $# -ge 2 ]] || die "Missing value for $1"; RESOURCE_PROFILE="$2"; shift 2 ;;
      --registry) [[ $# -ge 2 ]] || die "Missing value for $1"; REGISTRY_REPO="$2"; REGISTRY_REPO_EXPLICIT="true"; shift 2 ;;
      --registry-user) [[ $# -ge 2 ]] || die "Missing value for $1"; REGISTRY_USER="$2"; shift 2 ;;
      --registry-password|--registry-pass) [[ $# -ge 2 ]] || die "Missing value for $1"; REGISTRY_PASS="$2"; shift 2 ;;
      --image-pull-policy) [[ $# -ge 2 ]] || die "Missing value for $1"; IMAGE_PULL_POLICY="$2"; shift 2 ;;
      --skip-image-prepare) SKIP_IMAGE_PREPARE="true"; shift ;;
      --wait-timeout) [[ $# -ge 2 ]] || die "Missing value for $1"; WAIT_TIMEOUT="$2"; shift 2 ;;
      --enable-gateway) ENABLE_GATEWAY="true"; shift ;;
      --disable-gateway) ENABLE_GATEWAY="false"; shift ;;
      --require-gateway) REQUIRE_GATEWAY="true"; shift ;;
      --gateway-name) [[ $# -ge 2 ]] || die "Missing value for $1"; GATEWAY_NAME="$2"; shift 2 ;;
      --gateway-namespace) [[ $# -ge 2 ]] || die "Missing value for $1"; GATEWAY_NAMESPACE="$2"; shift 2 ;;
      --gateway-http-section) [[ $# -ge 2 ]] || die "Missing value for $1"; GATEWAY_HTTP_SECTION="$2"; shift 2 ;;
      --enable-ssh-route) ENABLE_SSH_ROUTE="true"; shift ;;
      --disable-ssh-route) ENABLE_SSH_ROUTE="false"; shift ;;
      --gateway-ssh-section) [[ $# -ge 2 ]] || die "Missing value for $1"; GATEWAY_SSH_SECTION="$2"; shift 2 ;;
      --ssh-external-port) [[ $# -ge 2 ]] || die "Missing value for $1"; SSH_EXTERNAL_PORT="$2"; shift 2 ;;
      --enable-oidc) ENABLE_OIDC="true"; shift ;;
      --disable-oidc) ENABLE_OIDC="false"; shift ;;
      --oidc-label) [[ $# -ge 2 ]] || die "Missing value for $1"; OIDC_PROVIDER_LABEL="$2"; shift 2 ;;
      --oidc-issuer) [[ $# -ge 2 ]] || die "Missing value for $1"; OIDC_ISSUER="$2"; shift 2 ;;
      --oidc-client-id) [[ $# -ge 2 ]] || die "Missing value for $1"; OIDC_CLIENT_ID="$2"; shift 2 ;;
      --oidc-client-secret) [[ $# -ge 2 ]] || die "Missing value for $1"; OIDC_CLIENT_SECRET="$2"; shift 2 ;;
      --oidc-redirect-uri) [[ $# -ge 2 ]] || die "Missing value for $1"; OIDC_REDIRECT_URI="$2"; shift 2 ;;
      --oidc-scope) [[ $# -ge 2 ]] || die "Missing value for $1"; OIDC_SCOPE="$2"; shift 2 ;;
      --oidc-uid-field) [[ $# -ge 2 ]] || die "Missing value for $1"; OIDC_UID_FIELD="$2"; shift 2 ;;
      --oidc-auto-sign-in) OIDC_AUTO_SIGN_IN="true"; shift ;;
      --delete-pvc) DELETE_PVC="true"; shift ;;
      -y|--yes) AUTO_YES="true"; shift ;;
      -h|--help) ACTION="help"; shift ;;
      *) die "Unknown argument: $1" ;;
    esac
  done
}

normalize_flags() {
  [[ -n "${EXTERNAL_URL}" ]] || EXTERNAL_URL="https://${HOSTNAME}"
  [[ -n "${OIDC_REDIRECT_URI}" ]] || OIDC_REDIRECT_URI="${EXTERNAL_URL%/}/users/auth/openid_connect/callback"
  case "${IMAGE_PULL_POLICY}" in Always|IfNotPresent|Never) ;; *) die "Unsupported image pull policy: ${IMAGE_PULL_POLICY}" ;; esac
  case "${RESOURCE_PROFILE,,}" in
    low) RESOURCE_PROFILE="low"; CPU_REQUEST="2"; CPU_LIMIT="4"; MEMORY_REQUEST="6Gi"; MEMORY_LIMIT="8Gi"; PUMA_WORKERS="2"; SIDEKIQ_CONCURRENCY="10" ;;
    mid|midd|middle|medium) RESOURCE_PROFILE="mid"; CPU_REQUEST="4"; CPU_LIMIT="8"; MEMORY_REQUEST="8Gi"; MEMORY_LIMIT="12Gi"; PUMA_WORKERS="3"; SIDEKIQ_CONCURRENCY="15" ;;
    high) RESOURCE_PROFILE="high"; CPU_REQUEST="8"; CPU_LIMIT="16"; MEMORY_REQUEST="16Gi"; MEMORY_LIMIT="24Gi"; PUMA_WORKERS="4"; SIDEKIQ_CONCURRENCY="25" ;;
    *) die "Unsupported resource profile: ${RESOURCE_PROFILE}. Expected low|mid|high" ;;
  esac
  if [[ "${ENABLE_OIDC}" == "true" ]]; then
    [[ -n "${OIDC_CLIENT_ID}" ]] || die "--oidc-client-id is required when --enable-oidc is used"
    [[ -n "${OIDC_CLIENT_SECRET}" ]] || die "--oidc-client-secret is required when --enable-oidc is used"
    [[ "${OIDC_ISSUER}" =~ ^https?:// ]] || die "--oidc-issuer must be an http(s) URL"
  fi
}

check_deps() {
  command -v kubectl >/dev/null 2>&1 || die "kubectl is required"
  if [[ "${ACTION}" == "install" && "${SKIP_IMAGE_PREPARE}" != "true" ]]; then
    command -v docker >/dev/null 2>&1 || die "docker is required unless --skip-image-prepare is used"
  fi
}

confirm() {
  [[ "${AUTO_YES}" == "true" ]] && return 0
  section "部署配置确认"
  echo "Action                  : ${ACTION}"
  echo "Release                 : ${RELEASE_NAME}"
  echo "Namespace               : ${NAMESPACE}"
  if [[ "${ACTION}" == "install" ]]; then
    echo "External URL            : ${EXTERNAL_URL}"
    echo "StorageClass            : ${STORAGE_CLASS}"
    echo "Config PVC              : ${CONFIG_STORAGE_SIZE}"
    echo "Logs PVC                : ${LOGS_STORAGE_SIZE}"
    echo "Data PVC                : ${DATA_STORAGE_SIZE}"
    echo "Resource profile        : ${RESOURCE_PROFILE} (${CPU_REQUEST}/${MEMORY_REQUEST} -> ${CPU_LIMIT}/${MEMORY_LIMIT})"
    echo "Gateway HTTPRoute       : ${ENABLE_GATEWAY} (${GATEWAY_NAMESPACE}/${GATEWAY_NAME}/${GATEWAY_HTTP_SECTION})"
    echo "Gateway SSH TCPRoute    : ${ENABLE_SSH_ROUTE} (${GATEWAY_SSH_SECTION})"
    echo "Casdoor OIDC            : ${ENABLE_OIDC}"
    echo "Registry repo           : ${REGISTRY_REPO}"
    echo "Skip image prepare      : ${SKIP_IMAGE_PREPARE}"
    echo "Wait timeout            : ${WAIT_TIMEOUT}"
  fi
  if [[ "${ACTION}" == "uninstall" ]]; then echo "Delete PVC              : ${DELETE_PVC}"; fi
  echo
  read -r -p "Continue? [y/N] " answer
  [[ "${answer}" =~ ^[Yy]$ ]] || die "Cancelled"
}

payload_start_offset() {
  local marker_line payload_offset skip_bytes byte_hex
  marker_line="$(awk '/^__PAYLOAD_BELOW__$/ { print NR; exit }' "$0")"
  [[ -n "${marker_line}" ]] || die "Payload marker not found"
  payload_offset="$(( $(head -n "${marker_line}" "$0" | wc -c | tr -d ' ') + 1 ))"
  skip_bytes=0
  while :; do
    byte_hex="$(dd if="$0" bs=1 skip="$((payload_offset + skip_bytes - 1))" count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')"
    case "${byte_hex}" in 0a|0d) skip_bytes=$((skip_bytes + 1)) ;; "") die "Payload is empty" ;; *) break ;; esac
  done
  printf '%s\n' "$((payload_offset + skip_bytes))"
}

extract_payload() {
  log "Extracting embedded payload to ${WORKDIR}"
  rm -rf "${WORKDIR}"
  mkdir -p "${WORKDIR}"
  tail -c +"$(payload_start_offset)" "$0" | tar -xzf - -C "${WORKDIR}" || die "Failed to extract payload"
  [[ -d "${MANIFEST_DIR}" ]] || die "Missing manifest payload"
  [[ -f "${IMAGE_INDEX}" ]] || die "Missing image metadata payload"
}

image_name_from_ref() { local ref="$1"; local name_tag="${ref##*/}"; echo "${name_tag%%:*}"; }
image_name_tag_from_ref() { local ref="$1"; echo "${ref##*/}"; }
resolve_target_ref() { local default_ref="$1"; if [[ "${REGISTRY_REPO_EXPLICIT}" == "true" ]]; then echo "${REGISTRY_REPO}/$(image_name_tag_from_ref "${default_ref}")"; else echo "${default_ref}"; fi; }

declare -A IMAGE_DEFAULT_TARGETS=()
declare -A IMAGE_EFFECTIVE_TARGETS=()
declare -A IMAGE_LOAD_REFS=()

load_image_metadata() {
  while IFS=$'\t' read -r tar_name load_ref default_target_ref; do
    [[ -n "${tar_name}" ]] || continue
    IMAGE_LOAD_REFS["${tar_name}"]="${load_ref}"
    IMAGE_DEFAULT_TARGETS["${tar_name}"]="${default_target_ref}"
    IMAGE_EFFECTIVE_TARGETS["${tar_name}"]="$(resolve_target_ref "${default_target_ref}")"
  done < "${IMAGE_INDEX}"
}

find_image_ref_by_name() {
  local wanted_name="$1" tar_name
  for tar_name in "${!IMAGE_EFFECTIVE_TARGETS[@]}"; do
    if [[ "$(image_name_from_ref "${IMAGE_EFFECTIVE_TARGETS[${tar_name}]}")" == "${wanted_name}" ]]; then echo "${IMAGE_EFFECTIVE_TARGETS[${tar_name}]}"; return 0; fi
  done
  return 1
}

docker_login() {
  local registry_host="${REGISTRY_REPO%%/*}"
  log "Logging into registry ${registry_host}"
  if ! echo "${REGISTRY_PASS}" | docker login "${registry_host}" -u "${REGISTRY_USER}" --password-stdin >/dev/null 2>&1; then warn "docker login failed for ${registry_host}; continuing and letting push decide"; fi
}

prepare_images() {
  [[ "${SKIP_IMAGE_PREPARE}" == "true" ]] && { log "Skipping image prepare because --skip-image-prepare was requested"; return 0; }
  docker_login
  local tar_name load_ref default_target_ref target_ref tar_path
  while IFS=$'\t' read -r tar_name load_ref default_target_ref; do
    [[ -n "${tar_name}" ]] || continue
    tar_path="${IMAGE_DIR}/${tar_name}"
    [[ -f "${tar_path}" ]] || die "Missing image tar: ${tar_path}"
    target_ref="${IMAGE_EFFECTIVE_TARGETS[${tar_name}]}"
    log "Loading ${tar_name}"
    docker load -i "${tar_path}" >/dev/null
    if [[ "${load_ref}" != "${target_ref}" ]]; then log "Tagging ${load_ref} -> ${target_ref}"; docker tag "${load_ref}" "${target_ref}"; fi
    log "Pushing ${target_ref}"
    docker push "${target_ref}"
  done < "${IMAGE_INDEX}"
  success "Image prepare completed"
}

ensure_namespace() { if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then log "Creating namespace ${NAMESPACE}"; kubectl create namespace "${NAMESPACE}" >/dev/null; fi; }

create_secret() {
  log "Creating or updating ${RELEASE_NAME}-secrets"
  kubectl -n "${NAMESPACE}" create secret generic "${RELEASE_NAME}-secrets" \
    --from-literal=root-password="${ROOT_PASSWORD}" \
    --from-literal=casdoor-client-secret="${OIDC_CLIENT_SECRET}" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
}

build_oidc_config_file() {
  local out="$1"
  : > "${out}"
  if [[ "${ENABLE_OIDC}" != "true" ]]; then
    cat >> "${out}" <<'OIDC_DISABLED'
    gitlab_rails['omniauth_enabled'] = false
OIDC_DISABLED
    return 0
  fi
  local auto_sign_in=""
  if [[ "${OIDC_AUTO_SIGN_IN}" == "true" ]]; then auto_sign_in="    gitlab_rails['omniauth_auto_sign_in_with_provider'] = 'openid_connect'"; fi
  cat >> "${out}" <<OIDC_ENABLED
    gitlab_rails['omniauth_enabled'] = true
    gitlab_rails['omniauth_allow_single_sign_on'] = ['openid_connect']
    gitlab_rails['omniauth_auto_link_user'] = ['openid_connect']
    gitlab_rails['omniauth_block_auto_created_users'] = false
    gitlab_rails['omniauth_sync_email_from_provider'] = 'openid_connect'
    gitlab_rails['omniauth_sync_profile_from_provider'] = ['openid_connect']
    gitlab_rails['omniauth_sync_profile_attributes'] = ['email']
${auto_sign_in}
    gitlab_rails['omniauth_providers'] = [
      {
        name: 'openid_connect',
        label: '${OIDC_PROVIDER_LABEL}',
        args: {
          name: 'openid_connect',
          scope: '${OIDC_SCOPE}',
          response_type: 'code',
          issuer: '${OIDC_ISSUER}',
          discovery: true,
          client_auth_method: 'query',
          uid_field: '${OIDC_UID_FIELD}',
          pkce: true,
          client_options: {
            identifier: '${OIDC_CLIENT_ID}',
            secret: ENV['CASDOOR_CLIENT_SECRET'],
            redirect_uri: '${OIDC_REDIRECT_URI}'
          }
        }
      }
    ]
OIDC_ENABLED
}

replace_placeholders() {
  local line="$1"
  line="${line//__NAMESPACE__/${NAMESPACE}}"
  line="${line//__RELEASE_NAME__/${RELEASE_NAME}}"
  line="${line//__HOSTNAME__/${HOSTNAME}}"
  line="${line//__EXTERNAL_URL__/${EXTERNAL_URL}}"
  line="${line//__TIMEZONE__/${TIMEZONE}}"
  line="${line//__GITLAB_IMAGE__/${GITLAB_IMAGE}}"
  line="${line//__IMAGE_PULL_POLICY__/${IMAGE_PULL_POLICY}}"
  line="${line//__STORAGE_CLASS__/${STORAGE_CLASS}}"
  line="${line//__CONFIG_STORAGE_SIZE__/${CONFIG_STORAGE_SIZE}}"
  line="${line//__LOGS_STORAGE_SIZE__/${LOGS_STORAGE_SIZE}}"
  line="${line//__DATA_STORAGE_SIZE__/${DATA_STORAGE_SIZE}}"
  line="${line//__CPU_REQUEST__/${CPU_REQUEST}}"
  line="${line//__CPU_LIMIT__/${CPU_LIMIT}}"
  line="${line//__MEMORY_REQUEST__/${MEMORY_REQUEST}}"
  line="${line//__MEMORY_LIMIT__/${MEMORY_LIMIT}}"
  line="${line//__PUMA_WORKERS__/${PUMA_WORKERS}}"
  line="${line//__SIDEKIQ_CONCURRENCY__/${SIDEKIQ_CONCURRENCY}}"
  line="${line//__ENABLE_EMBEDDED_PROMETHEUS__/${ENABLE_EMBEDDED_PROMETHEUS}}"
  line="${line//__GATEWAY_NAME__/${GATEWAY_NAME}}"
  line="${line//__GATEWAY_NAMESPACE__/${GATEWAY_NAMESPACE}}"
  line="${line//__GATEWAY_HTTP_SECTION__/${GATEWAY_HTTP_SECTION}}"
  line="${line//__GATEWAY_SSH_SECTION__/${GATEWAY_SSH_SECTION}}"
  line="${line//__SSH_EXTERNAL_PORT__/${SSH_EXTERNAL_PORT}}"
  printf '%s\n' "${line}"
}

render_template() {
  local template="$1" output="$2" oidc_config_file="$3" line
  : > "${output}"
  while IFS= read -r line || [[ -n "${line}" ]]; do
    if [[ "${line}" == "__OIDC_CONFIG__" ]]; then cat "${oidc_config_file}" >> "${output}"; else replace_placeholders "${line}" >> "${output}"; fi
  done < "${template}"
}

render_and_apply() { local template="$1" rendered="$2" oidc_config_file="$3"; render_template "${template}" "${rendered}" "${oidc_config_file}"; kubectl apply -f "${rendered}"; }
has_crd() { local crd="$1"; kubectl get crd "${crd}" >/dev/null 2>&1; }

apply_gateway_routes() {
  local oidc_config_file="$1"
  [[ "${ENABLE_GATEWAY}" == "true" ]] || return 0
  if ! has_crd "httproutes.gateway.networking.k8s.io"; then
    if [[ "${REQUIRE_GATEWAY}" == "true" ]]; then die "HTTPRoute CRD not found; install Envoy Gateway/Gateway API first or remove --require-gateway"; fi
    warn "HTTPRoute CRD not found; skipping Gateway API HTTPRoute"
    return 0
  fi
  render_and_apply "${MANIFEST_DIR}/50-httproute.yaml.tmpl" "${WORKDIR}/50-httproute.yaml" "${oidc_config_file}"
  if [[ "${ENABLE_SSH_ROUTE}" == "true" ]]; then
    if has_crd "tcproutes.gateway.networking.k8s.io"; then render_and_apply "${MANIFEST_DIR}/55-tcproute.yaml.tmpl" "${WORKDIR}/55-tcproute.yaml" "${oidc_config_file}"; else warn "TCPRoute CRD not found; skipping SSH TCPRoute"; fi
  fi
}

install_release() {
  GITLAB_IMAGE="$(find_image_ref_by_name "gitlab-ce")" || die "Unable to resolve gitlab-ce image"
  local oidc_config_file="${WORKDIR}/oidc-config.rb"
  build_oidc_config_file "${oidc_config_file}"
  ensure_namespace
  create_secret
  render_and_apply "${MANIFEST_DIR}/10-configmap.yaml.tmpl" "${WORKDIR}/10-configmap.yaml" "${oidc_config_file}"
  render_and_apply "${MANIFEST_DIR}/20-service.yaml.tmpl" "${WORKDIR}/20-service.yaml" "${oidc_config_file}"
  render_and_apply "${MANIFEST_DIR}/30-statefulset.yaml.tmpl" "${WORKDIR}/30-statefulset.yaml" "${oidc_config_file}"
  render_and_apply "${MANIFEST_DIR}/40-pdb.yaml.tmpl" "${WORKDIR}/40-pdb.yaml" "${oidc_config_file}"
  apply_gateway_routes "${oidc_config_file}"
  section "等待 GitLab StatefulSet 就绪"
  kubectl rollout status "statefulset/${RELEASE_NAME}" -n "${NAMESPACE}" --timeout="${WAIT_TIMEOUT}"
  success "GitLab install or upgrade completed"
}

show_post_install_info() {
  section "部署结果"
  kubectl get statefulset,pods,svc,pvc -n "${NAMESPACE}" -l "app.kubernetes.io/instance=${RELEASE_NAME}" || true
  if has_crd "httproutes.gateway.networking.k8s.io"; then echo; kubectl get httproute -n "${NAMESPACE}" "${RELEASE_NAME}-http" || true; fi
  if has_crd "tcproutes.gateway.networking.k8s.io"; then echo; kubectl get tcproute -n "${NAMESPACE}" "${RELEASE_NAME}-ssh" || true; fi
  cat <<EOF_INFO

GitLab URL:
  ${EXTERNAL_URL}

Root login:
  username: root
  password: use the value passed by --root-password on first initialization

Casdoor redirect URI when OIDC is enabled:
  ${OIDC_REDIRECT_URI}

Notes:
  First boot can take several minutes because Omnibus initializes PostgreSQL, Redis, Gitaly and Rails.
  PVCs are preserved on uninstall unless --delete-pvc is explicitly used.
EOF_INFO
}

status_release() {
  section "GitLab 状态"
  kubectl get statefulset,pods,svc,pvc -n "${NAMESPACE}" -l "app.kubernetes.io/instance=${RELEASE_NAME}" || true
  echo
  kubectl describe statefulset "${RELEASE_NAME}" -n "${NAMESPACE}" 2>/dev/null | sed -n '1,120p' || true
  if has_crd "httproutes.gateway.networking.k8s.io"; then echo; kubectl get httproute -n "${NAMESPACE}" "${RELEASE_NAME}-http" || true; fi
  if has_crd "tcproutes.gateway.networking.k8s.io"; then echo; kubectl get tcproute -n "${NAMESPACE}" "${RELEASE_NAME}-ssh" || true; fi
}

uninstall_release() {
  section "卸载 GitLab 资源"
  if has_crd "tcproutes.gateway.networking.k8s.io"; then kubectl delete tcproute "${RELEASE_NAME}-ssh" -n "${NAMESPACE}" --ignore-not-found=true; fi
  if has_crd "httproutes.gateway.networking.k8s.io"; then kubectl delete httproute "${RELEASE_NAME}-http" -n "${NAMESPACE}" --ignore-not-found=true; fi
  kubectl delete pdb "${RELEASE_NAME}" -n "${NAMESPACE}" --ignore-not-found=true
  kubectl delete statefulset "${RELEASE_NAME}" -n "${NAMESPACE}" --ignore-not-found=true
  kubectl delete svc "${RELEASE_NAME}" -n "${NAMESPACE}" --ignore-not-found=true
  kubectl delete configmap "${RELEASE_NAME}-config" -n "${NAMESPACE}" --ignore-not-found=true
  kubectl delete secret "${RELEASE_NAME}-secrets" -n "${NAMESPACE}" --ignore-not-found=true
  if [[ "${DELETE_PVC}" == "true" ]]; then warn "Deleting PVCs for ${RELEASE_NAME} in ${NAMESPACE}"; kubectl delete pvc -n "${NAMESPACE}" -l "app.kubernetes.io/instance=${RELEASE_NAME}" --ignore-not-found=true; else warn "PVCs are preserved. Use --delete-pvc to remove data volumes explicitly."; fi
  success "Uninstall completed"
}

main() {
  parse_args "$@"
  normalize_flags
  if [[ "${ACTION}" == "help" ]]; then usage; exit 0; fi
  check_deps
  confirm
  case "${ACTION}" in
    install) extract_payload; load_image_metadata; prepare_images; install_release; show_post_install_info ;;
    status) status_release ;;
    uninstall) uninstall_release ;;
    *) usage; die "Unsupported action: ${ACTION}" ;;
  esac
}

main "$@"
exit 0

__PAYLOAD_BELOW__
