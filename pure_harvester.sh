#!/usr/bin/env bash

# https://github.com/clemenko/rke2
# this script assumes digitalocean is setup with DNS.
# you need doctl, kubectl, uuid, jq, k3sup, pdsh and curl installed.
# clemenko@gmail.com 

###################################
# edit varsw
###################################
set -e
num=3
password=Pa22word
domain=rfed.io

# rancher / k8s
prefix=rke # no rke k3s
k8s_version=stable

######  NO MOAR EDITS #######
#export PDSH_RCMD_TYPE=ssh

#better error checking
command -v doctl >/dev/null 2>&1 || { fatal "Doctl was not found. Please install" ; }
command -v curl >/dev/null 2>&1 || { fatal "Curl was not found. Please install" ; }
command -v jq >/dev/null 2>&1 || { fatal "Jq was not found. Please install" ; }
command -v pdsh >/dev/null 2>&1 || { fatal "Pdsh was not found. Please install" ; }
command -v k3sup >/dev/null 2>&1 || { fatal "K3sup was not found. Please install" ; }
command -v kubectl >/dev/null 2>&1 || { fatal "Kubectl was not found. Please install" ; }

source functions.sh

# update helm
helm repo update > /dev/null 2>&1

################################# up ################################
function up () {
build_list=""
# helm repo update > /dev/null 2>&1

#rando list generation
for i in $(seq 1 $num); do build_list="$build_list $prefix$i"; done

#build VMS
echo -e -n " - building vms -$build_list"
harvester vm create --template farock --count $num rke > /dev/null 2>&1 || fatal "vms did not build"
info_ok

echo -e -n "   - waiting for vms to boot "
until [ $(harvester vm list | grep Running | wc -l ) = 3 ]; do echo -e -n "." ; sleep 10; done
sleep 30
info_ok

touch ip.txt
for i in $(harvester vm list |grep -v NAME | grep Run | grep $prefix | awk '{print $6}'); do 
  echo $(harvester vm list |grep -v NAME | grep Run | grep $i| awk '{print $2}') " "$(ssh root@$i "ip a show eth0 |grep -w inet | awk '{print \$2}'|sed 's#/24##g'") >> ip.txt
done

#check for SSH
echo -e -n " - checking for ssh "
for ext in $(cat ip.txt | awk '{print $2}'); do
  until [ $(ssh -o ConnectTimeout=1 root@$ext 'exit' 2>&1 | grep 'timed out\|refused' | wc -l) = 0 ]; do echo -e -n "." ; sleep 5; done
done
info_ok

#get ips
host_list=$(cat ip.txt | awk '{printf $2","}' | sed 's/,$//')
server=$(cat ip.txt | sed -n 1p | awk '{print $2}')
worker_list=$(cat ip.txt | sed 1d | awk '{printf $2","}' | sed 's/,$//')

#update DNS
echo -e -n " - updating dns"
doctl compute domain records create $domain --record-type A --record-name $prefix --record-ttl 60 --record-data $server > /dev/null 2>&1
doctl compute domain records create $domain --record-type CNAME --record-name "*" --record-ttl 60 --record-data $prefix.$domain. > /dev/null 2>&1
info_ok

#add centos packagkes
centos_packages

#kernel tuning from functions
kernel

#or deploy rke2
if [ "$prefix" = rke ]; then
  echo -e -n "$BLUE" "deploying rke2" "$NO_COLOR"

  # systemctl disable nm-cloud-setup.service nm-cloud-setup.timer
  
  ssh root@$server 'mkdir -p /var/lib/rancher/rke2/server/manifests/ /etc/rancher/rke2/; useradd -r -c "etcd user" -s /sbin/nologin -M etcd -U; echo -e "apiVersion: audit.k8s.io/v1\nkind: Policy\nmetadata:\n  name: rke2-audit-policy\nrules:\n  - level: Metadata\n    resources:\n    - group: \"\"\n      resources: [\"secrets\"]\n  - level: RequestResponse\n    resources:\n    - group: \"\"\n      resources: [\"*\"]" > /etc/rancher/rke2/audit-policy.yaml; echo -e "#profile: cis\n#selinux: true\nsecrets-encryption: true\ntoken: bootstrapAllTheThings\ntls-san:\n- rke."'$domain'"\nwrite-kubeconfig-mode: 0600\n#pod-security-admission-config-file: /etc/rancher/rke2/rancher-psact.yaml\nkube-controller-manager-arg:\n- bind-address=127.0.0.1\n- use-service-account-credentials=true\n- tls-min-version=VersionTLS12\n- tls-cipher-suites=TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384\nkube-scheduler-arg:\n- tls-min-version=VersionTLS12\n- tls-cipher-suites=TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384\nkube-apiserver-arg:\n- tls-min-version=VersionTLS12\n- tls-cipher-suites=TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384\n- authorization-mode=RBAC,Node\n- anonymous-auth=false\n- audit-policy-file=/etc/rancher/rke2/audit-policy.yaml\n- audit-log-mode=blocking-strict\n- audit-log-maxage=30\nkubelet-arg:\n- kube-reserved=cpu=400m,memory=1Gi\n- system-reserved=cpu=400m,memory=1Gi\n- protect-kernel-defaults=true\n- read-only-port=0\n- authorization-mode=Webhook\n- streaming-connection-idle-timeout=5m\n- max-pods=400" > /etc/rancher/rke2/config.yaml;  curl -s https://raw.githubusercontent.com/clemenko/k8s_yaml/master/rancher-psact.yaml -o /etc/rancher/rke2/rancher-psact.yaml ; echo -e "apiVersion: helm.cattle.io/v1\nkind: HelmChartConfig\nmetadata:\n  name: rke2-ingress-nginx\n  namespace: kube-system\nspec:\n  valuesContent: |-\n    controller:\n      config:\n        use-forwarded-headers: true\n      extraArgs:\n        enable-ssl-passthrough: true" > /var/lib/rancher/rke2/server/manifests/rke2-ingress-nginx-config.yaml; curl -sfL https://get.rke2.io | INSTALL_RKE2_CHANNEL='$k8s_version' sh - ; systemctl enable --now rke2-server.service' > /dev/null 2>&1

  sleep 15

  pdsh -l root -w $worker_list 'curl -sfL https://get.rke2.io | INSTALL_RKE2_CHANNEL='$k8s_version' INSTALL_RKE2_TYPE=agent sh - && echo -e "#selinux: true\nserver: https://"'$server'":9345\ntoken: bootstrapAllTheThings\nprofile: cis\nkubelet-arg:\n- protect-kernel-defaults=true\n- read-only-port=0\n- authorization-mode=Webhook" > /etc/rancher/rke2/config.yaml; systemctl enable --now rke2-agent.service' > /dev/null 2>&1

  ssh root@$server cat /etc/rancher/rke2/rke2.yaml | sed -e "s/127.0.0.1/$server/g" > ~/.kube/config 
  chmod 0600 ~/.kube/config

  info_ok
fi

echo -e -n " - cluster active "
sleep 10
until [ $(kubectl get node|grep NotReady|wc -l) = 0 ]; do echo -e -n "."; sleep 2; done
sleep 10
info_ok
}

############################## kill ################################
#remove the vms
function kill () {

  echo -e -n " killing it all "
  harvester vm delete $(harvester vm |grep -v NAME | grep $prefix | awk '{printf $2" "}') > /dev/null 2>&1
  for i in $(cat ip.txt | awk '{print $2}'); do ssh-keygen -q -R $i > /dev/null 2>&1; done
  for i in $(doctl compute domain records list $domain|grep rke |awk '{print $1}'); do doctl compute domain records delete -f $domain $i; done

  rm -rf *.txt *.log *.zip *.pub env.* certs backup.tar ~/.kube/config central* sensor* *token kubeconfig *TOKEN 

info_ok
}

case "$1" in
        up) up;;
        kill) kill;;
        px) portworx;;
        longhorn) longhorn;;
        rancher) rancher;;
        demo) demo;;
        fleet) fleet;;
        *) usage;;
esac
