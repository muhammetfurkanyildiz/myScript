#!/bin/bash

#############################################
# KUBERNETES OTOMATİK KURULUM SCRIPTİ
# Bastion Host üzerinden
# Container Runtime: containerd
# Kubernetes Repo: pkgs.k8s.io (yeni sistem)
#############################################

# NODE Listesi (hostname;ip)
NODES=(
    "tonton;192.168.1.104"   # Master
    "asker;192.168.1.114"    # Worker
    "concon;192.168.1.124"   # Worker
)

# İlk node’u otomatik master seç
MASTER_NODE="${NODES[0]}"
MASTER_HOSTNAME=$(echo $MASTER_NODE | cut -d';' -f1)
MASTER_IP=$(echo $MASTER_NODE | cut -d';' -f2)

POD_CIDR="192.168.0.0/16"

echo
echo "===== KUBERNETES OTOMATİK KURULUM BAŞLIYOR ====="
echo "Master Node: $MASTER_HOSTNAME ($MASTER_IP)"
echo

#############################################
# SSH Komut Fonksiyonu
#############################################
ssh_exec() {
    local HOST=$1
    local IP=$2
    local CMD=$3

    echo "[ $HOST | $IP ] -> Komut Çalıştırılıyor..."
    ssh -o StrictHostKeyChecking=no ${HOST}@${IP} "$CMD"

    if [ $? -ne 0 ]; then
        echo "HATA: $HOST üzerinde komut çalıştırılamadı!"
        exit 1
    fi
}

#############################################
# Tüm Node'larda Hazırlık Komutları
#############################################
PREP_CMDS="
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Kernel modülleri
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Sysctl Ayarları
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

sudo sysctl --system

# Gerekli paketler
sudo apt update -y
sudo apt install -y curl apt-transport-https ca-certificates gnupg lsb-release

# Containerd kur
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu \$(lsb_release -cs) stable\" \
| sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update -y
sudo apt install -y containerd.io

sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml

sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

sudo systemctl restart containerd
sudo systemctl enable containerd

# Kubernetes repo yeni sistem
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | \
    sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo \"deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /\" | \
sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt update -y
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
"

echo "---- 1. ADIM: TÜM NODE'LAR HAZIRLANIYOR ----"
for NODE in "${NODES[@]}"; do
    HOST=$(echo $NODE | cut -d';' -f1)
    IP=$(echo $NODE | cut -d';' -f2)
    ssh_exec $HOST $IP "$PREP_CMDS"
done

#############################################
# MASTER KURULUMU
#############################################
echo
echo "---- 2. ADIM: MASTER NODE KURULUYOR ----"

MASTER_CMDS="
sudo kubeadm init \
  --apiserver-advertise-address=$MASTER_IP \
  --pod-network-cidr=$POD_CIDR

mkdir -p \$HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf \$HOME/.kube/config
sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config
"

ssh_exec $MASTER_HOSTNAME $MASTER_IP "$MASTER_CMDS"

#############################################
# Worker Join Komutunu Alma
#############################################
echo
echo "---- 3. ADIM: JOIN KOMUTU ALINIYOR ----"

JOIN_CMD=$(ssh ${MASTER_HOSTNAME}@${MASTER_IP} "kubeadm token create --print-join-command")

echo "JOIN KOMUTU:"
echo "$JOIN_CMD"
echo

#############################################
# WORKER NODE'LERİN KATILMASI
#############################################
echo "---- 4. ADIM: WORKER NODE'LER KÜMEYE EKLENİYOR ----"

for NODE in "${NODES[@]}"; do
    HOST=$(echo $NODE | cut -d';' -f1)
    IP=$(echo $NODE | cut -d';' -f2)

    if [ "$IP" == "$MASTER_IP" ]; then
        continue
    fi

    ssh_exec $HOST $IP "sudo $JOIN_CMD"
done

#############################################
# CNI (Calico) Kurulumu
#############################################
echo
echo "---- 5. ADIM: CALICO YÜKLENİYOR ----"

ssh_exec $MASTER_HOSTNAME $MASTER_IP "
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.3/manifests/calico.yaml
"

#############################################
# TAMAMLANDI
#############################################
echo
echo "===== KURULUM TAMAMLANDI ====="
echo "Master node’a bağlanıp kontrol edebilirsiniz:"
echo
echo "ssh $MASTER_HOSTNAME@$MASTER_IP"
echo "kubectl get nodes"
echo
