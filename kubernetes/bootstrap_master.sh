#!/usr/bin/env bash
# Kubernetes Bootstrap_master Master Node Script (Debian-based only)
# Features: Dry-Run, Verbosity, Error Handling, Task Listing, Selective Execution

# ==========================
# DEFAULT CONFIG
# ==========================
API_SERVER_ADDR="172.16.16.100"                 # --api-addr / -a
POD_NETWORK_CIDR="192.168.0.0/16"               # --pod-cidr / -c
CALICO_VERSION="v3.31.2"                        # --calico-ver / -C
CALICO_DATAPLANE="iptables"                     # --calico-dp / -D (choices: iptables|bpf)
USER_HOME="/root"                       # --user-home / -U (default for Vagrant)
JOIN_SCRIPT_DIR="/srv/join"                     # --join-dir / -j

DRY_RUN=false
VERBOSE=false
ONLY=""
SKIP=""
LIST_TASKS=false

# ==========================
# CLI HELP
# ==========================
print_usage() {
  cat <<'EOF'
bootstrap_master.sh — Initialize Kubernetes control plane (Debian-based only)

USAGE:
  sudo ./bootstrap_master.sh [options]

OPTIONS:
  --dry-run, -d                 Preview commands without executing them
  --verbose, -v                 Print commands for each task
  --api-addr, -a <IP>           API server advertise address (default: 172.16.16.100)
  --pod-cidr, -c <CIDR>         Pod network CIDR (default: 192.168.0.0/16)
  --calico-ver, -C <ver>        Calico version tag (default: v3.31.2)
  --calico-dp, -D <mode>        Calico dataplane (iptables|bpf, default: iptables)
  --user-home, -U <path>        Home directory for kubeconfig (default: /home/vagrant)
  --join-dir, -j <path>         Directory to write join script (default: /srv/join)
  --only, -o "1,2"              Run only specified task numbers
  --skip, -s "3"                Skip specified task numbers
  --list-tasks, -t              List all tasks and exit
  --help, -?                    Show this help

EXAMPLES:
  sudo ./bootstrap_master.sh -t
  sudo ./bootstrap_master.sh -d
  sudo ./bootstrap_master.sh -d -v
  sudo ./bootstrap_master.sh -a 10.0.0.10 -c 10.244.0.0/16
  sudo ./bootstrap_master.sh -D bpf
  sudo ./bootstrap_master.sh -U /home/deepak
EOF
}

# ==========================
# CLI ARGUMENTS
# ==========================
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run|-d) DRY_RUN=true ;;
    --verbose|-v) VERBOSE=true ;;
    --api-addr|-a) API_SERVER_ADDR="$2"; shift ;;
    --pod-cidr|-c) POD_NETWORK_CIDR="$2"; shift ;;
    --calico-ver|-C) CALICO_VERSION="$2"; shift ;;
    --calico-dp|-D) CALICO_DATAPLANE="$2"; shift ;;
    --user-home|-U) USER_HOME="$2"; shift ;;
    --join-dir|-j) JOIN_SCRIPT_DIR="$2"; shift ;;
    --only|-o) ONLY="$2"; shift ;;
    --skip|-s) SKIP="$2"; shift ;;
    --list-tasks|-t) LIST_TASKS=true ;;
    --help|-?) print_usage; exit 0 ;;
    *) echo "Unknown option: $1"; print_usage; exit 1 ;;
  esac
  shift
done

# ==========================
# SAFETY & ENVIRONMENT CHECKS
# ==========================
set -eo pipefail
trap 'echo -e "### \u274C [ERROR] Script failed at task $TASK_NUM." >&2' ERR

OS_ID="$(awk -F= '/^ID=/{print $2}' /etc/os-release | tr -d '"')"
if [[ "$OS_ID" != "debian" && "$OS_ID" != "ubuntu" ]]; then
  echo -e "### \u274C [ERROR] This script supports Debian-based OS only. Detected: $OS_ID"
  exit 1
fi

# Check apt availability
if ! command -v apt &>/dev/null; then
  echo -e "### \u274C [ERROR] apt not found. This script requires apt package manager."
  exit 1
fi

# Pre-check required tools
REQUIRED_TOOLS=(curl gpg modprobe systemctl)
for tool in "${REQUIRED_TOOLS[@]}"; do
  if ! command -v "$tool" &>/dev/null; then
    echo -e "### \u274C [ERROR] Required tool '$tool' is missing. Please install it before running this script."
    echo "        Try: apt update && apt install -y kubeadm kubectl curl"
    exit 1
  fi
done

export DEBIAN_FRONTEND=noninteractive

# ==========================
# TASK CONTROL HELPERS
# ==========================
TASK_NUM=0
TASK_LIST=()

contains_number() {
  local list="$1" num="$2"
  [[ -z "$list" ]] && return 1
  IFS=',' read -r -a arr <<< "$list"
  for x in "${arr[@]}"; do
    [[ "$x" =~ ^[0-9]+$ ]] && [[ "$x" -eq "$num" ]] && return 0
  done
  return 1
}
should_run() {
  local num="$1"
  if [[ -n "$ONLY" ]]; then
    contains_number "$ONLY" "$num" || return 1
  fi
  if contains_number "$SKIP" "$num"; then
    return 1
  fi
  return 0
}

TASK() {
  TASK_NUM=$((TASK_NUM + 1))
  local desc="$1"
  TASK_LIST+=("### \u2638\uFE0F  \033[1m[TASK $TASK_NUM]\033[0m $desc")
  local cmd; cmd="$(cat)"

  if $LIST_TASKS; then return; fi

  if ! should_run "$TASK_NUM"; then
    echo -e "### \u2638\uFE0F  \033[1m[TASK $TASK_NUM]\033[0m $desc (skipped)"
    return
  fi
  echo -e "### \u2638\uFE0F  \033[1m[TASK $TASK_NUM]\033[0m $desc"
  if $DRY_RUN; then
    if $VERBOSE; then
      echo "$cmd"
      echo
    else
      echo -e "### \u2638\uFE0F  \033[1m[DRY-RUN]\033[0m (commands suppressed; use -v to show)"
      echo
    fi
  else
    if $VERBOSE; then
      echo "$cmd"
      echo
    fi
    bash -euo pipefail -c "$cmd"
  fi
}

# ==========================
# TASKS
# ==========================
TASK "Pull required Kubernetes control-plane images (optional)" <<'CMD'
# kubeadm config images pull >/dev/null
true
CMD

TASK "Initialize Kubernetes Cluster with kubeadm" <<CMD
kubeadm init \
  --apiserver-advertise-address "$API_SERVER_ADDR" \
  --pod-network-cidr "$POD_NETWORK_CIDR"
CMD

TASK "Copy kube admin config to USER_HOME ($USER_HOME)" <<CMD
mkdir -p $USER_HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf "$USER_HOME/.kube/config"
sudo chown $USER:$USER "$USER_HOME/.kube"
CMD

TASK "Deploy Calico CNI via Tigera Operator ($CALICO_VERSION, $CALICO_DATAPLANE)" <<CMD
kubectl create -f "https://raw.githubusercontent.com/projectcalico/calico/$CALICO_VERSION/manifests/operator-crds.yaml" &>/dev/null
kubectl create -f "https://raw.githubusercontent.com/projectcalico/calico/$CALICO_VERSION/manifests/tigera-operator.yaml" &>/dev/null

if [[ "$CALICO_DATAPLANE" == "bpf" ]]; then
  kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/$CALICO_VERSION/manifests/custom-resources-bpf.yaml &>/dev/null
else # "$CALICO_DATAPLANE" == "iptables" -- Default
  kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/$CALICO_VERSION/manifests/custom-resources.yaml &>/dev/null
fi
CMD

TASK "Generate and save cluster join command" <<CMD
mkdir -p "$JOIN_SCRIPT_DIR"
kubeadm token create --print-join-command > "$JOIN_SCRIPT_DIR/joincluster.sh"
chmod +x "$JOIN_SCRIPT_DIR/joincluster.sh"
CMD

# ==========================
# LIST TASKS MODE
# ==========================
if $LIST_TASKS; then
  echo "Available tasks:"
  for t in "${TASK_LIST[@]}"; do
    echo -e "  $t"
  done
  exit 0
fi

echo -e "### \u2705 \033[1m[FINAL]\033[0m All tasks completed."
