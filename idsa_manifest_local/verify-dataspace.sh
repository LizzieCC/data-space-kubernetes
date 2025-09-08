#!/usr/bin/env bash
set -euo pipefail

NS="ids-2"
# Permite: ./verify-dataspace.sh -n <namespace>
while getopts ":n:" opt; do
  case $opt in
    n) NS="$OPTARG" ;;
    \?) echo "Uso: $0 [-n <namespace>]"; exit 1 ;;
  esac
done

# ---- utilidades de salida ----
GREEN="\033[0;32m"; RED="\033[0;31m"; YELLOW="\033[1;33m"; NC="\033[0m"
ok()   { printf "${GREEN}OK${NC}\n"; }
fail() { printf "${RED}FAIL${NC}\n"; }
warn() { printf "${YELLOW}WARN${NC}\n"; }

# ---- acumuladores de resultado ----
RC=0
RES_DAPS_CONFIG=""; RES_DAPS_JWKS=""
RES_FUSEKI_DATASET=""; RES_FUSEKI_ASK=""
RES_BROKER_CORE=""; RES_CONNA=""; RES_CONNB=""
RES_DEPLOYMENTS=""

# ---- 1) Estado de despliegues/servicios/pods ----
echo "==[1/4] Comprobación de recursos Kubernetes en namespace '${NS}'=="
if ! kubectl get ns "${NS}" >/dev/null 2>&1; then
  echo -e "Namespace '${NS}': $(fail)"
  exit 1
fi

echo "- Deployments esperados disponibles:"
expected_deploys=(omejdn-server omejdn omejdn-ui broker-core broker-fuseki broker-reverseproxy connectora connectorb)
avail_ok=true
for d in "${expected_deploys[@]}"; do
  # available replicas >= 1
  AVAIL=$(kubectl get deploy "$d" -n "${NS}" -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo "")
  if [[ -n "$AVAIL" && "$AVAIL" -ge 1 ]]; then
    printf "  %-24s : " "$d"; ok
  else
    printf "  %-24s : " "$d"; fail
    avail_ok=false
  fi
done
RES_DEPLOYMENTS=$([[ "$avail_ok" == "true" ]] && echo "OK" || echo "FAIL")
[[ "$avail_ok" == "true" ]] || RC=1

echo
echo "==[2/4] Creación de pod efímero para pruebas de red internas=="
# Creamos un pod 'ds-verify' con curl; si existe, lo reciclamos
kubectl -n "${NS}" delete pod ds-verify --ignore-not-found >/dev/null 2>&1 || true
kubectl -n "${NS}" run ds-verify --image=curlimages/curl:8.10.1 --restart=Never -- sleep 300 >/dev/null
echo -n "Esperando a que 'ds-verify' esté listo..."
kubectl -n "${NS}" wait --for=condition=Ready pod/ds-verify --timeout=30s >/dev/null && echo " listo."

# Helper para ejecutar dentro del pod y capturar salida
incurl() { kubectl -n "${NS}" exec ds-verify -- sh -c "$*"; }

echo
echo "==[3/4] Pruebas de conectividad y endpoints=="

# ---- DAPS (Omejdn) ----
echo "- DAPS (Omejdn): /.well-known/openid-configuration"
code=$(incurl "curl -s -o /dev/null -w \"%{http_code}\" http://omejdn/auth/.well-known/openid-configuration" || true)
if [[ "$code" == "200" ]]; then RES_DAPS_CONFIG="OK"; ok; else RES_DAPS_CONFIG="FAIL"; fail; RC=1; fi

echo "- DAPS (Omejdn): /auth/jwks.json"
jwks_body=$(incurl "curl -s http://omejdn/auth/jwks.json" || true)
if echo "$jwks_body" | grep -q '"keys"'; then RES_DAPS_JWKS="OK"; ok; else RES_DAPS_JWKS="FAIL"; fail; RC=1; fi

# ---- Fuseki (dataset y consulta mínima) ----
echo "- Fuseki dataset (connectorData) accesible"
code=$(incurl "curl -s -o /dev/null -w \"%{http_code}\" http://broker-fuseki:3030/connectorData" || true)
if [[ "$code" == "200" ]]; then RES_FUSEKI_DATASET="OK"; ok; else RES_FUSEKI_DATASET="FAIL"; fail; RC=1; fi

echo "- Fuseki SPARQL ASK {}"
ask=$(incurl "curl -s -X POST -H 'Content-Type: application/sparql-query' --data 'ASK {}' http://broker-fuseki:3030/connectorData/sparql" || true)
# Aceptamos 'true' en cualquier capitalización, con o sin espacios
if echo "$ask" | tr '[:upper:]' '[:lower:]' | grep -q "true"; then RES_FUSEKI_ASK="OK"; ok; else RES_FUSEKI_ASK="FAIL"; fail; RC=1; fi

# ---- Broker-core ----
echo "- broker-core HTTP (8080)"
code=$(incurl "curl -s -o /dev/null -w \"%{http_code}\" http://broker-core:8080/" || true)
# aceptamos 200..399
if [[ "$code" =~ ^(2|3)[0-9]{2}$ ]]; then RES_BROKER_CORE="OK"; ok; else RES_BROKER_CORE="FAIL"; fail; RC=1; fi

# ---- Conectores (IDS-HTTP; TLS autofirmado; GET puede devolver 405/401) ----
echo "- Connector A IDS endpoint (https://connectora:8080/api/ids/data)"
code=$(incurl "curl -k -s -o /dev/null -w \"%{http_code}\" https://connectora:8080/api/ids/data" || true)
# consideramos OK cualquier 2xx-4xx (incluye 401/403/405); 5xx es fallo o inalcanzable
if [[ "$code" =~ ^[2-4][0-9]{2}$ ]]; then RES_CONNA="OK"; ok; else RES_CONNA="FAIL"; fail; RC=1; fi

echo "- Connector B IDS endpoint (https://connectorb:8081/api/ids/data)"
code=$(incurl "curl -k -s -o /dev/null -w \"%{http_code}\" https://connectorb:8081/api/ids/data" || true)
if [[ "$code" =~ ^[2-4][0-9]{2}$ ]]; then RES_CONNB="OK"; ok; else RES_CONNB="FAIL"; fail; RC=1; fi

echo
echo "==[4/4] Limpieza de pod efímero=="
kubectl -n "${NS}" delete pod ds-verify --ignore-not-found >/dev/null 2>&1 || true
echo "Limpieza completa."

echo
echo "================= RESUMEN ================="
printf "%-28s : %s\n" "Deployments disponibles"     "$RES_DEPLOYMENTS"
printf "%-28s : %s\n" "DAPS openid-configuration"    "$RES_DAPS_CONFIG"
printf "%-28s : %s\n" "DAPS JWKS"                    "$RES_DAPS_JWKS"
printf "%-28s : %s\n" "Fuseki dataset"               "$RES_FUSEKI_DATASET"
printf "%-28s : %s\n" "Fuseki SPARQL ASK"            "$RES_FUSEKI_ASK"
printf "%-28s : %s\n" "broker-core HTTP"             "$RES_BROKER_CORE"
printf "%-28s : %s\n" "connectorA IDS endpoint"      "$RES_CONNA"
printf "%-28s : %s\n" "connectorB IDS endpoint"      "$RES_CONNB"
echo "=========================================="
exit "$RC"
