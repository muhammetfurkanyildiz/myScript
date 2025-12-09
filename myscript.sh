#!/bin/bash
# KUBERNETES OTOMATİK KURULUM SCRİPTİ (Bastion Üzerinden)
# DAĞITIM: Ubuntu/Debian (APT tabanlı)
# CONTAINER RUNTIME: Containerd
# KULLANICI ADI: Her sunucunun hostname'i kullanıcı adı olarak kabul edilir.

# 1. PARAMETRELERİ AYARLA
# Format: "hostname;IP_adresi"
NODES=(
    "tonton;192.168.1.104" # Master Node olacak
    "asker;192.168.1.114"
    "concon;192.168.1.124"
)

# Otomatik Master Seçimi: İlk Node'u Master olarak atarız
MASTER_NODE_INFO="${NODES[0]}" # tonton;192.168.1.104
MASTER_HOSTNAME=$(echo $MASTER_NODE_INFO | cut -d';' -f1) # tonton (Aynı zamanda kullanıcı adı)
MASTER_IP=$(echo $MASTER_NODE_INFO | cut -d';' -f2)      # 192.168.1.104
POD_CIDR="192.168.0.0/16" # Calico için varsayılan CIDR

echo "--- K8s Kurulumu Başlatılıyor ---"
echo "Master Node: $MASTER_HOSTNAME ($MASTER_IP)"
echo "---"

# Uzak Komut Çalıştırma Fonksiyonu
ssh_calistir() {
    local HOSTNAME=$1 # Bu aynı zamanda SSH kullanıcı adı olarak kullanılacak (örn: tonton)
    local IP=$2
    local KOMUT=$3
    
    local USERNAME=$HOSTNAME # Hostname'i kullanıcı adı olarak kullanıyoruz

    echo "[$HOSTNAME ($IP)] Komut Çalıştırılıyor: $KOMUT"
    # SSH komutu: ssh hostname@IP 'KOMUT'
    # Şifresiz SSH erişiminin (ssh-copy-id) kurulmuş olması gerekir!
    ssh -o StrictHostKeyChecking=no ${USERNAME}@${IP} "${KOMUT}"
    if [ $? -ne 0 ]; then
        echo "HATA: $HOSTNAME ($IP) üzerinde komut başarısız oldu. Lütfen kontrol edin."
        # exit 1 
    fi
}

# 2. ÖN HAZIRLIK (TÜM NODE'LAR)
echo "## 2. Tüm Node'larda Ön Hazırlık Başlatılıyor (Containerd ve K8s Paketleri)..."

PREP_KOMUTU="
# 1. Swap'ı Kapat
sudo swapoff -a;
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab;

# 2. Kernel Modüllerini Yükle
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

# 3. Sysctl Parametrelerini Ayarla
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system

# 4. Containerd Kurulumu (Ubuntu/Debian) - Değişiklik Yok
sudo apt update;
sudo apt install -y ca-certificates curl gnupg lsb-release;
sudo mkdir -p /etc/apt/keyrings;
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg;
echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \$(lsb_release -cs) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null;

sudo apt update;
sudo apt install -y containerd.io;
sudo mkdir -p /etc/containerd;
containerd config default | sudo tee /etc/containerd/config.toml;
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml;
sudo systemctl restart containerd;
sudo systemctl enable containerd;

# 5. YENİ Kubernetes Paketleri Kurulumu (kubeadm, kubelet, kubectl)
# Yeni Depo: pkgs.k8s.io ve yeni GPG anahtar yönetimi

# Kubernetes GPG anahtarını indir
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg;

# Yeni Kubernetes deposunu ekle
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list;

# Paketleri kur
sudo apt update;
sudo apt install -y kubelet kubeadm kubectl;
sudo apt-mark hold kubelet kubeadm kubectl;
"
# Kernel Modüllerini Yükle
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

# Sysctl Parametrelerini Ayarla
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system

# Containerd Kurulumu (Ubuntu/Debian)
sudo apt update;
sudo apt install -y ca-certificates curl gnupg lsb-release;
sudo mkdir -p /etc/apt/keyrings;
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg;
echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \$(lsb_release -cs) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null;

sudo apt update;
sudo apt install -y containerd.io;
sudo mkdir -p /etc/containerd;
containerd config default | sudo tee /etc/containerd/config.toml;
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml;
sudo systemctl restart containerd;
sudo systemctl enable containerd;

# Kubernetes Paketleri (kubeadm, kubelet, kubectl) Kurulumu
sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg;
echo \"deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main\" | sudo tee /etc/apt/sources.list.d/kubernetes.list;

sudo apt update;
sudo apt install -y kubelet kubeadm kubectl;
sudo apt-mark hold kubelet kubeadm kubectl;
"

for NODE_INFO in "${NODES[@]}"; do
    HOSTNAME=$(echo $NODE_INFO | cut -d';' -f1)
    IP=$(echo $NODE_INFO | cut -d';' -f2)
    ssh_calistir $HOSTNAME $IP "$PREP_KOMUTU"
done

# 3. MASTER NODE BAŞLATMA
echo "## 3. Master Node ($MASTER_HOSTNAME) Başlatılıyor..."

MASTER_KOMUTU="
sudo kubeadm init --apiserver-advertise-address=$MASTER_IP --pod-network-cidr=$POD_CIDR;
# Kubectl'i kullanabilmek için gerekli ayarlar
mkdir -p \$HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf \$HOME/.kube/config
sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config
"

ssh_calistir $MASTER_HOSTNAME $MASTER_IP "$MASTER_KOMUTU"

# 4. JOIN COMMAND ALMA
echo "## 4. Worker'lar için Join Komutu Alınıyor..."

# Join komutunu Master node'dan alıyoruz.
JOIN_COMMAND=$(ssh ${MASTER_HOSTNAME}@${MASTER_IP} "sudo kubeadm token create --print-join-command")

if [ -z "$JOIN_COMMAND" ]; then
    echo "HATA: Master'dan join komutu alınamadı. Lütfen Master'daki kurulumu kontrol edin."
    exit 1
fi

echo "Alınan Join Komutu: $JOIN_COMMAND"

# 5. WORKER NODE'LARIN KÜMEYE KATILMASI
echo "## 5. Worker Node'lar Kümeye Katılıyor..."

for NODE_INFO in "${NODES[@]}"; do
    HOSTNAME=$(echo $NODE_INFO | cut -d';' -f1)
    IP=$(echo $NODE_INFO | cut -d';' -f2)

    # Master node'u atla
    if [ "$IP" == "$MASTER_IP" ]; then
        echo "[$HOSTNAME] Master node atlanıyor."
        continue
    fi

    echo "[$HOSTNAME] Worker olarak kümeye katılıyor..."
    WORKER_KOMUTU="sudo $JOIN_COMMAND"
    ssh_calistir $HOSTNAME $IP "$WORKER_KOMUTU"
done

# 6. POD AĞINI (CNI) KURMA
echo "## 6. Pod Ağı (Calico) Kuruluyor (Master Üzerinde)..."

# CNI'yı (Calico) Master Node'da çalıştırıyoruz.
CNI_KOMUTU="
# Calico kurulum dosyası (v3.27)
kubectl --kubeconfig=\$HOME/.kube/config apply -f https://docs.tigera.io/calico/latest/manifests/calico.yaml
"
ssh_calistir $MASTER_HOSTNAME $MASTER_IP "$CNI_KOMUTU"

# 7. SON KONTROL
echo "--- KURULUM TAMAMLANDI ---"
echo "Kümeyi kontrol etmek için Master Node'a SSH ile bağlanın:"
echo "ssh $MASTER_HOSTNAME@$MASTER_IP"
echo "Komut: kubectl get nodes"
