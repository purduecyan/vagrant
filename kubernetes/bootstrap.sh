#!/usr/bin/env bash
# Kubernetes Node Setup Script for Debian-based OS only
# Features: Dry-Run, Verbosity, Error Handling, Configurable Hosts, Task Listing

# ==========================
# DEFAULT CONFIG
# ==========================
ROOT_PASSWORD="kubeadmin"
K8S_VERSION="v1.34"
CONTAINER_RUNTIME="containerd"
HOST_ENTRIES="
172.16.16.100   master.example.com     master
172.16.16.101   worker1.example.com    worker1
172.16.16.102   worker2.example.com    worker2
"
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
bootstrap.sh — Kubernetes Node Setup (Debian-based only)

USAGE:
  sudo ./bootstrap.sh [options]

OPTIONS:
  --dry-run, -d                 Preview commands without executing them
  --verbose, -v                 Print commands for each task
  --host, -H "<IP FQDN alias>"  Add a single host entry (can be used multiple times)
  --root-password, -p <pass>    Root password (default: kubeadmin)
  --k8s-version, -k <ver>       Kubernetes apt repo version
  --runtime, -r <name>          Container runtime (default: containerd)
  --only, -o "1,2,7"            Run only specified task numbers
  --skip, -s "3,4"              Skip specified task numbers
  --list-tasks, -t              List all tasks and exit
  --help, -h                    Show this help

EXAMPLES:
  # List all tasks
  sudo ./bootstrap.sh --list-tasks
  sudo ./bootstrap.sh -t

  # Dry-run everything
  sudo ./bootstrap.sh -d
  sudo ./bootstrap.sh -d -v   # verbose dry-run. Use this to print all commands to run in a script 

  # Run only Task 5
  sudo ./bootstrap.sh -o "5"

  # Add extra hosts
  sudo ./bootstrap.sh -H "172.16.16.103 node3.example.com node3"
EOF
}

# ==========================
# CLI ARGUMENTS
# ==========================
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run|-d) DRY_RUN=true ;;
    --verbose|-v) VERBOSE=true ;;
    --host|-H) HOST_ENTRIES+=$'\n'"$2"; shift ;;
    --root-password|-p) ROOT_PASSWORD="$2"; shift ;;
    --k8s-version|-k) K8S_VERSION="$2"; shift ;;
    --runtime|-r) CONTAINER_RUNTIME="$2"; shift ;;
    --only|-o) ONLY="$2"; shift ;;
    --skip|-s) SKIP="$2"; shift ;;
    --list-tasks|-t) LIST_TASKS=true ;;
    --help|-h) print_usage; exit 0 ;;
    *) echo "Unknown option: $1"; print_usage; exit 1 ;;
  esac
  shift
done

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
# SAFETY & ENVIRONMENT CHECKS
# ==========================
set -euo pipefail
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
    exit 1
  fi
done

# Set non-interactive mode for apt
export DEBIAN_FRONTEND=noninteractive

# ==========================
# TASKS
# ==========================
TASK "Disable and turn off SWAP" <<'CMD'
sed -i '/swap/d' /etc/fstab
swapoff -a || true
CMD

TASK "Stop and Disable firewall (ufw)" <<'CMD'
systemctl disable --now ufw &>/dev/null || true
CMD

TASK "Enable and Load Kernel modules" <<'CMD'
cat >/etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter
CMD

TASK "Add Kernel settings for Kubernetes networking" <<'CMD'
cat >/etc/sysctl.d/kubernetes.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system &>/dev/null
CMD

TASK "Install container runtime ($CONTAINER_RUNTIME)" <<CMD
apt update -qq &> /dev/null
apt install -qq -y apt-transport-https ca-certificates curl gnupg lsb-release &> /dev/null
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/$OS_ID/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS_ID $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
apt update -qq &> /dev/null
apt install -qq -y containerd.io &> /dev/null
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd &>/dev/null
CMD

TASK "Set up Kubernetes apt repo ($K8S_VERSION)" <<CMD
mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/$K8S_VERSION/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/$K8S_VERSION/deb/ /" > /etc/apt/sources.list.d/kubernetes.list
CMD

TASK "Install Kubernetes components (kubeadm, kubelet, kubectl)" <<'CMD'
apt update -qq &> /dev/null
apt install -qq -y kubeadm kubelet kubectl &> /dev/null
apt-mark hold kubeadm kubelet kubectl &> /dev/null
CMD

TASK "Enable SSH password authentication" <<'CMD'
sed -i 's/^PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config
grep -q '^PermitRootLogin' /etc/ssh/sshd_config && \
  sed -i 's/^PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config || \
  echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config
systemctl reload sshd
CMD

TASK "Set root password and terminal" <<CMD
echo -e "$ROOT_PASSWORD\n$ROOT_PASSWORD" | passwd root &>/dev/null
echo "export TERM=xterm" >> /etc/bash.bashrc
CMD

TASK "Update /etc/hosts file" <<CMD
cat >> /etc/hosts <<'EOF'
$HOST_ENTRIES
EOF
CMD

# Add more TASKs as needed...
# ==========================
# Example:
# TASK "Description of the task" <<'CMD'
# echo "Commands to execute"
# CMD


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
