# ── Locals ────────────────────────────────────────────────────────────────────

locals {
  # Absolute path where the kubeconfig will be written on the Mac host.
  # pathexpand resolves the leading "~" so subsequent providers can consume it.
  kubeconfig_path = pathexpand("${var.kubeconfig_dir}/k3s-homelab.yaml")
}

# ── Step 1: Verify the Lima VM is running ─────────────────────────────────────
#
# Fails early with a helpful message rather than letting limactl hang
# trying to connect to a stopped VM.

resource "null_resource" "verify_vm" {
  triggers = {
    vm_name = var.lima_vm_name
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-BASH
      set -euo pipefail
      if ! limactl shell "${var.lima_vm_name}" -- echo "VM is reachable" 2>/dev/null; then
        echo ""
        echo "ERROR: Lima VM '${var.lima_vm_name}' is not running or not reachable."
        echo "Start it with:  limactl start --name=${var.lima_vm_name} vm/lima.yaml"
        echo ""
        exit 1
      fi
    BASH
  }
}

# ── Step 2: Install k3s on the Lima VM ────────────────────────────────────────
#
# Runs entirely inside the VM via `limactl shell` (which uses Lima's managed SSH
# connection — no manual key setup needed).
#
# Flags explained:
#   --disable traefik     Remove the built-in ingress controller (we manage this
#                         separately or not at all in a homelab context).
#   --disable servicelb   Remove k3s's built-in LoadBalancer controller so we
#                         don't conflict with MetalLB/other LB solutions.
#   --tls-san 127.0.0.1   Include 127.0.0.1 in the API server TLS certificate so
#                         kubectl on the Mac host (via Lima port-forward) works.
#   --write-kubeconfig-mode 644
#                         Make the kubeconfig readable by non-root users inside
#                         the VM so we can copy it without sudo cat.
#
# The install script is idempotent: it skips installation if k3s is already at
# the requested version.

resource "null_resource" "k3s_install" {
  depends_on = [null_resource.verify_vm]

  # Changing k3s_version re-triggers this resource so upgrades work.
  triggers = {
    k3s_version = var.k3s_version
    vm_name     = var.lima_vm_name
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-BASH
      set -euo pipefail

      echo "==> Installing k3s ${var.k3s_version} on VM '${var.lima_vm_name}'..."

      # Write the install script to a temp file and copy it into the VM.
      # This avoids all quoting/escaping issues with nested shells.
      SCRIPT_FILE=$(mktemp /tmp/k3s-install-XXXXXX.sh)
      cat > "$SCRIPT_FILE" << 'INSTALL_SCRIPT'
#!/bin/bash
set -euo pipefail
K3S_TARGET_VERSION="__K3S_VERSION__"

# Idempotency check — skip if already at the target version
if command -v k3s &>/dev/null; then
  CURRENT=$(k3s --version 2>/dev/null | awk '{print $3}')
  if [ "$CURRENT" = "$K3S_TARGET_VERSION" ]; then
    echo "k3s $K3S_TARGET_VERSION is already installed. Skipping."
    exit 0
  fi
  echo "Found k3s $CURRENT, upgrading to $K3S_TARGET_VERSION..."
fi

echo "Downloading and installing k3s $K3S_TARGET_VERSION..."
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_VERSION="$K3S_TARGET_VERSION" \
  INSTALL_K3S_EXEC="server --disable traefik --disable servicelb --tls-san 127.0.0.1 --write-kubeconfig-mode 644" \
  sudo sh -

echo "Waiting for k3s node to reach Ready state (up to 2 min)..."
for i in $(seq 1 24); do
  if sudo k3s kubectl get nodes 2>/dev/null | grep -qE '\bReady\b'; then
    echo "Node is Ready!"
    sudo k3s kubectl get nodes
    exit 0
  fi
  echo "  Still waiting... attempt $i/24"
  sleep 5
done

echo "ERROR: k3s node did not become Ready within 120 seconds."
sudo k3s kubectl get nodes || true
sudo journalctl -u k3s --no-pager -n 50 || true
exit 1
INSTALL_SCRIPT

      # Substitute the version placeholder now that we're in plain bash
      sed -i '' "s/__K3S_VERSION__/${var.k3s_version}/g" "$SCRIPT_FILE"

      # Copy the script into the VM and run it
      limactl copy "$SCRIPT_FILE" "${var.lima_vm_name}:/tmp/k3s-install.sh"
      limactl shell "${var.lima_vm_name}" -- sudo bash /tmp/k3s-install.sh
      rm -f "$SCRIPT_FILE"
    BASH
  }
}

# ── Step 3: Copy kubeconfig to the Mac host ───────────────────────────────────
#
# k3s writes its kubeconfig to /etc/rancher/k3s/k3s.yaml inside the VM.
# The server address is https://127.0.0.1:6443.
#
# Because Lima forwards guest port 6443 → host 127.0.0.1:6443, this kubeconfig
# works as-is from the Mac without any address rewriting.

resource "null_resource" "kubeconfig" {
  depends_on = [null_resource.k3s_install]

  triggers = {
    k3s_version     = var.k3s_version
    kubeconfig_path = local.kubeconfig_path
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-BASH
      set -euo pipefail

      KUBECONFIG_PATH="${local.kubeconfig_path}"
      KUBECONFIG_DIR="$(dirname "$KUBECONFIG_PATH")"

      echo "==> Copying kubeconfig from VM to $KUBECONFIG_PATH..."

      mkdir -p "$KUBECONFIG_DIR"

      # k3s writes the file with mode 644 (--write-kubeconfig-mode 644) so
      # we can read it as the default lima user without sudo.
      limactl shell "${var.lima_vm_name}" -- cat /etc/rancher/k3s/k3s.yaml \
        > "$KUBECONFIG_PATH"

      # Tighten permissions — kubeconfig contains a client certificate.
      chmod 600 "$KUBECONFIG_PATH"

      echo "Kubeconfig written to $KUBECONFIG_PATH"
    BASH
  }
}

# ── Step 4: Smoke-test cluster connectivity ───────────────────────────────────
#
# Verifies that kubectl on the Mac host can reach the API server through the
# Lima port-forward before declaring bootstrap complete.

resource "null_resource" "verify_cluster" {
  depends_on = [null_resource.kubeconfig]

  triggers = {
    kubeconfig_path = local.kubeconfig_path
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-BASH
      set -euo pipefail
      echo "==> Verifying cluster connectivity from Mac host..."
      kubectl --kubeconfig="${local.kubeconfig_path}" get nodes
      kubectl --kubeconfig="${local.kubeconfig_path}" get namespaces
      echo ""
      echo "Bootstrap complete! Cluster is reachable."
      echo "  KUBECONFIG=${local.kubeconfig_path}"
    BASH
  }
}
