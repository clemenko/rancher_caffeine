#!/usr/bin/env bash

# functions
# color
export RED='\x1b[0;31m'
export GREEN='\x1b[32m'
export BLUE='\x1b[34m'
export YELLOW='\x1b[33m'
export NO_COLOR='\x1b[0m'

# set functions for debugging/logging
function info { echo -e "$GREEN[info]$NO_COLOR $1" ;  }
function warn { echo -e "$YELLOW[warn]$NO_COLOR $1" ; }
function fatal { echo -e "$RED[error]$NO_COLOR $1" ; exit 1 ; }
function info_ok { echo -e "$GREEN"" ok""$NO_COLOR" ; }

#gov logon message
export govmessage=$(cat <<EOF
You are accessing a U.S. Government (USG) Information System (IS) that is provided for USG-authorized use only.By using this IS (which includes any device attached to this IS), you consent to the following conditions:-The USG routinely intercepts and monitors communications on this IS for purposes including, but not limited to, penetration testing, COMSEC monitoring, network operations and defense, personnel misconduct (PM), law enforcement (LE), and counterintelligence (CI) investigations.-At any time, the USG may inspect and seize data stored on this IS.-Communications using, or data stored on, this IS are not private, are subject to routine monitoring, interception, and search, and may be disclosed or used for any USG-authorized purpose.-This IS includes security measures (e.g., authentication and access controls) to protect USG interests--not for your personal benefit or privacy.-Notwithstanding the above, using this IS does not constitute consent to PM, LE or CI investigative searching or monitoring of the content of privileged communications, or work product, related to personal representation or services by attorneys, psychotherapists, or clergy, and their assistants. Such communications and work product are private and confidential. See User Agreement for details.
EOF
)


############################# usage ################################
function usage () {
  echo -e ""
  echo -e "-------------------------------------------------"
  echo -e ""
  echo -e " Usage: $0 {up|kill|tl|rancher|demo|full}"
  echo -e ""
  echo -e " ${BLUE} $0 up # build the vms ${NO_COLOR}"
  echo -e " ${RED}$0 rancher # rancher will build cluster if not present${NO_COLOR}"
  echo -e " $0 demo # deploy demo apps"
  echo -e " $0 fleet # deploy fleet apps"
  echo -e " $0 kill # kill the vms"
  echo -e " $0 full # full send"
  echo -e ""
  echo -e "-------------------------------------------------"
  echo -e ""
  exit 1
}

############################# os_packages ################################
function centos_packages () {
# adding centos packages.
echo -e -n " - adding os packages"
pdsh -l root -w $host_list 'echo -e "[keyfile]\nunmanaged-devices=interface-name:cali*;interface-name:flannel*" > /etc/NetworkManager/conf.d/rke2-canal.conf; yum install -y nfs-utils cryptsetup iscsi-initiator-utils iptables-services iptables-utils device-mapper-multipath; systemctl enable --now iscsid; yum update openssh -y; #yum update -y' > /dev/null 2>&1
info_ok
}

############################# kernel ################################
function kernel () {
#kernel tuning
echo -e -n " - updating kernel settings"
pdsh -l root -w $host_list 'cat << EOF >> /etc/sysctl.conf
# SWAP settings
vm.swappiness=0
vm.panic_on_oom=0
vm.overcommit_memory=1
kernel.panic=10
kernel.panic_on_oops=1
vm.max_map_count = 262144
net.ipv4.ip_local_port_range=1024 65000
net.core.somaxconn=10000
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_fin_timeout=15
net.core.somaxconn=4096
net.core.netdev_max_backlog=4096
net.core.rmem_max=536870912
net.core.wmem_max=536870912
net.ipv4.tcp_max_syn_backlog=20480
net.ipv4.tcp_max_tw_buckets=400000
net.ipv4.tcp_no_metrics_save=1
net.ipv4.tcp_rmem=4096 87380 268435456
net.ipv4.tcp_wmem=4096 87380 268435456
net.ipv4.tcp_syn_retries=2
net.ipv4.tcp_synack_retries=2
net.ipv4.neigh.default.gc_thresh1=8096
net.ipv4.neigh.default.gc_thresh2=12288
net.ipv4.neigh.default.gc_thresh3=16384
net.ipv4.tcp_keepalive_time=600
net.ipv4.ip_forward=1
fs.inotify.max_user_instances=8192
fs.inotify.max_user_watches=1048576
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF
sysctl -p' > /dev/null 2>&1
info_ok
}

################################ portworx ##############################
function portworx () {

echo -e  " - adding px-csi"

host_list=$(cat ip.txt | awk '{printf $2","}' | sed 's/,$//')

echo -e -n "   - adding multipath"
pdsh -l root -w $host_list 'cat << EOF >> /etc/multipath.conf
devices {
    device {
        vendor                      "NVME"
        product                     "Pure Storage FlashArray"
        path_selector               "queue-length 0"
        path_grouping_policy        group_by_prio
        prio                        ana
        failback                    immediate
        fast_io_fail_tmo            10
        user_friendly_names         no
        no_path_retry               0
        features                    0
        dev_loss_tmo                60
    }
    device {
        vendor                   "PURE"
        product                  "FlashArray"
        path_selector            "service-time 0"
        hardware_handler         "1 alua"
        path_grouping_policy     group_by_prio
        prio                     alua
        failback                 immediate
        path_checker             tur
        fast_io_fail_tmo         10
        user_friendly_names      no
        no_path_retry            0
        features                 0
        dev_loss_tmo             600
    }
}
blacklist_exceptions {
    property "(SCSI_IDENT_|ID_WWN)"
}
blacklist {
    devnode "^pxd[0-9]*"
    devnode "^pxd*"
    device {
        vendor "VMware"
        product "Virtual disk"
    }
    device {
        vendor "IET"
        product "VIRTUAL-DISK"
    }
}
EOF
yum install -y device-mapper-multipath
systemctl restart multipathd' > /dev/null 2>&1
info_ok

# get latest version of PX-CSI
PX_CSI_VER=$(curl -sL https://dzver.rfed.io/json | jq -r .portworx)

# create namespace
kubectl create ns portworx > /dev/null 2>&1

# create and add secret
cat << EOF > pure.json 
{
    "FlashArrays": [
        {
            "MgmtEndPoint": "192.168.1.11",
            "APIToken": "934f95b6-6d1d-ee91-d210-6ed9bce13ad1",
            "NFSEndPoint": "192.168.1.8"
        }
    ]
}
EOF

kubectl create secret generic px-pure-secret -n portworx --from-file=pure.json=pure.json > /dev/null 2>&1

echo -e -n "   - adding operator and storaecluster"

# apply operator yaml
kubectl apply -f 'https://install.portworx.com/'$PX_CSI_VER'?comp=pxoperator&oem=px-csi&kbver=1.33.5&ns=portworx' > /dev/null 2>&1

kubectl wait --for condition=containersready -n portworx pod --all > /dev/null 2>&1

sleep 10

cat << EOF | kubectl apply -n portworx  -f -
kind: StorageCluster
apiVersion: core.libopenstorage.org/v1
metadata:
  name: px-cluster
  namespace: portworx
  annotations:
    portworx.io/misc-args: "--oem px-csi"
    #portworx.io/health-check: "skip"
spec:
  image: portworx/px-pure-csi-driver:$PX_CSI_VER
  imagePullPolicy: IfNotPresent
  csi:
    enabled: true
  monitoring:
    telemetry:
      enabled: false
    prometheus:
      enabled: false
      exportMetrics: false
  env:
  - name: PURE_FLASHARRAY_SAN_TYPE
    value: "ISCSI"
EOF

sleep 30

kubectl wait --for condition=containersready -n portworx pod --all > /dev/null 2>&1

kubectl patch storageclass px-fa-direct-access -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' > /dev/null 2>&1 

info_ok

}

################################ rancher ##############################
function rancher () {

  if [[ ! -f ip.txt ]] && ! kubectl get node > /dev/null 2>&1 ; then
    echo -e "$BLUE" "Building cluster first." "$NO_COLOR"
    up && longhorn
  fi

  echo -e "$BLUE" "deploying rancher" "$NO_COLOR"

  echo -e -n " - helm - cert-manager"
  helm upgrade -i cert-manager cert-manager --repo https://charts.jetstack.io -n cert-manager --create-namespace --set crds.enabled=true > /dev/null 2>&1 
  
  info_ok
  
  echo -e -n " - helm - rancher"

  # custom TLS certs
  kubectl create ns cattle-system > /dev/null 2>&1 
  kubectl -n cattle-system create secret tls tls-rancher-ingress --cert=/Users/clemenko/Dropbox/work/rfed.me/io/star.rfed.io.cert --key=/Users/clemenko/Dropbox/work/rfed.me/io/star.rfed.io.key > /dev/null 2>&1 
  kubectl -n cattle-system create secret generic tls-ca --from-file=/Users/clemenko/Dropbox/work/rfed.me/io/cacerts.pem > /dev/null 2>&1 

  helm upgrade -i rancher rancher --repo https://releases.rancher.com/server-charts/latest -n cattle-system --create-namespace --set hostname=rancher.$domain --set bootstrapPassword=bootStrapAllTheThings --set replicas=1 --set auditLog.level=2 --set auditLog.destination=hostPath --set auditLog.hostPath=/var/log/rancher/audit --set auditLog.maxAge=30 --set antiAffinity=required --set antiAffinity=required  --set ingress.tls.source=secret --set ingress.tls.secretName=tls-rancher-ingress --set privateCA=true --set 'extraEnv[0].name=CATTLE_FEATURES' --set 'extraEnv[0].value=ui-sql-cache=true' > /dev/null 2>&1

  info_ok

  # wait for rancher
  echo -e -n " - waiting for rancher"
  until [ $(curl -sk https://rancher.$domain/v3-public/authproviders | grep local | wc -l ) = 1 ]; do 
    sleep 2; echo -e -n "."; done

  info_ok

  echo -e -n " - bootstrapping"
cat <<EOF | kubectl apply -f -  > /dev/null 2>&1
apiVersion: management.cattle.io/v3
kind: Setting
metadata:
  name: password-min-length
  namespace: cattle-system
value: "8"
EOF

  #set password
  token=$(curl -sk -X POST https://rancher.$domain/v3-public/localProviders/local?action=login -H 'content-type: application/json' -d '{"username":"admin","password":"bootStrapAllTheThings"}' | jq -r .token)

  curl -sk https://rancher.$domain/v3/users?action=changepassword -H 'content-type: application/json' -H "Authorization: Bearer $token" -d '{"currentPassword":"bootStrapAllTheThings","newPassword":"'$password'"}'  > /dev/null 2>&1 

  api_token=$(curl -sk https://rancher.$domain/v3/token -H 'content-type: application/json' -H "Authorization: Bearer $token" -d '{"type":"token","description":"automation"}' | jq -r .token)

  curl -sk https://rancher.$domain/v3/settings/server-url -H 'content-type: application/json' -H "Authorization: Bearer $api_token" -X PUT -d '{"name":"server-url","value":"https://rancher.'$domain'"}'  > /dev/null 2>&1

  curl -sk https://rancher.$domain/v3/settings/telemetry-opt -X PUT -H 'content-type: application/json' -H 'accept: application/json' -H "Authorization: Bearer $api_token" -d '{"value":"out"}' > /dev/null 2>&1

  info_ok

  # class banners
cat <<EOF | kubectl apply -f -  > /dev/null 2>&1
apiVersion: management.cattle.io/v3
kind: Setting
metadata:
  name: ui-banners
value: '{"bannerHeader":{"background":"#007a33","color":"#ffffff","textAlignment":"center","fontWeight":null,"fontStyle":null,"fontSize":"14px","textDecoration":null,"text":"UNCLASSIFIED//FOUO"},"bannerFooter":{"background":"#007a33","color":"#ffffff","textAlignment":"center","fontWeight":null,"fontStyle":null,"fontSize":"14px","textDecoration":null,"text":"UNCLASSIFIED//FOUO"},"bannerConsent":{"background":"#ffffff","color":"#000000","textAlignment":"left","fontWeight":null,"fontStyle":null,"fontSize":"14px","textDecoration":false,"text":"$govmessage","button":"Accept"},"showHeader":"true","showFooter":"true","showConsent":"true"}'
EOF

}

################################ longhorn ##############################
function longhorn () {
  echo -e -n  " - longhorn"

  # to http basic auth --> https://longhorn.io/docs/1.4.1/deploy/accessing-the-ui/longhorn-ingress/

  helm upgrade -i longhorn longhorn --repo https://charts.longhorn.io -n longhorn-system --create-namespace --set ingress.enabled=true,ingress.host=longhorn.$domain  > /dev/null 2>&1 
  
  #,defaultSettings.allowCollectingLonghornUsageMetrics=false,persistence.defaultDataLocality="best-effort" --set persistence.dataEngine=v2 --set defaultSettings.v2DataEngine=true --set defaultSettings.v1DataEngine=false > /dev/null 2>&1 

  sleep 5

  #wait for longhorn to initiaize
  until [ $(kubectl get pod -n longhorn-system | grep -v 'Running\|NAME' | wc -l) = 0 ] && [ "$(kubectl get pod -n longhorn-system | wc -l)" -gt 19 ] ; do echo -e -n "." ; sleep 2; done
  # testing out ` kubectl wait --for condition=containersready -n longhorn-system pod --all`

  if [ "$prefix" = k3s ]; then kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}' > /dev/null 2>&1; fi

  # add encryption per volume storage class 
  kubectl apply -f https://raw.githubusercontent.com/clemenko/k8s_yaml/master/longhorn_encryption.yml > /dev/null 2>&1

  info_ok
}

############################# fleet ################################
function fleet () {
  echo -e -n " fleet-ing"
  #kubectl create secret -n cattle-global-data generic docreds --from-literal=digitaloceancredentialConfig-accessToken=${DO_TOKEN} > /dev/null 2>&1

  kubectl apply -f https://raw.githubusercontent.com/clemenko/fleet/main/gitrepo.yml > /dev/null 2>&1
  
  info_ok
}

############################# demo ################################
function demo () {
  echo -e " demo-ing"

  echo -e -n " - flask ";kubectl apply -f https://raw.githubusercontent.com/clemenko/k8s_yaml/master/flask_simple_nginx.yml > /dev/null 2>&1; info_ok
  
  echo -e -n " - minio"
  helm upgrade -i minio minio --repo https://charts.min.io -n minio --set rootUser=admin,rootPassword=$password --create-namespace --set mode=standalone --set resources.requests.memory=1Gi --set persistence.size=10Gi --set mode=standalone --set ingress.enabled=true --set ingress.hosts[0]=s3.$domain --set consoleIngress.enabled=true --set consoleIngress.hosts[0]=minio.$domain --set ingress.annotations."nginx\.ingress\.kubernetes\.io/proxy-body-size"="1024m" --set consoleIngress.annotations."nginx\.ingress\.kubernetes\.io/proxy-body-size"="1024m" --set image.repository=cgr.dev/chainguard/minio --set image.tag=latest > /dev/null 2>&1
  info_ok

  echo -e -n " - harbor"
  helm upgrade -i harbor harbor --repo https://helm.goharbor.io -n harbor --create-namespace --set expose.tls.certSource=secret --set expose.tls.secret.secretName=tls-ingress --set expose.tls.enabled=false --set expose.tls.auto.commonName=harbor.$domain --set expose.ingress.hosts.core=harbor.$domain --set persistence.enabled=true --set harborAdminPassword=$password --set externalURL=http://harbor.$domain --set notary.enabled=false > /dev/null 2>&1;
  info_ok

  echo -e -n " - gitea"
  helm upgrade -i gitea oci://registry-1.docker.io/giteacharts/gitea -n gitea --create-namespace --set gitea.admin.password=$password --set gitea.admin.username=gitea --set persistence.size=2500Mi --set ingress.enabled=true --set ingress.hosts[0].host=git.$domain --set ingress.hosts[0].paths[0].path=/ --set ingress.hosts[0].paths[0].pathType=Prefix --set gitea.config.server.DOMAIN=git.$domain --set postgresql-ha.enabled=false --set valkey-cluster.enabled=false --set gitea.config.database.DB_TYPE=sqlite3 --set gitea.config.session.PROVIDER=memory  --set gitea.config.cache.ADAPTER=memory --set gitea.config.queue.TYPE=level > /dev/null 2>&1

  # mirror github
  until [ $(curl -s http://git.$domain/explore/repos| grep "<title>" | wc -l) = 1 ]; do sleep 2; echo -n "."; done

  sleep 5
  
  curl -X POST http://git.$domain/api/v1/repos/migrate -H 'accept: application/json' -H 'authorization: Basic Z2l0ZWE6UGEyMndvcmQ=' -H 'Content-Type: application/json' -d '{ "clone_addr": "https://github.com/clemenko/fleet", "repo_name": "fleet","repo_owner": "gitea"}' > /dev/null 2>&1
  
  curl -X POST http://git.$domain/api/v1/repos/migrate -H 'accept: application/json' -H 'authorization: Basic Z2l0ZWE6UGEyMndvcmQ=' -H 'Content-Type: application/json' -d '{ "clone_addr": "https://github.com/clemenko/rancher_caffeine", "repo_name": "rancher_caffeine","repo_owner": "gitea"}' > /dev/null 2>&1

  info_ok

  echo -e -n " - postgresql "
  helm upgrade -i postgresql oci://registry-1.docker.io/bitnamicharts/postgresql -n postgresql --create-namespace  --set global.postgresql.auth.postgresPassword=Pa22word,primary.persistence.storageClass=px-fa-direct-access,primary.persistence.size=12Gi > /dev/null 2>&1
  info_ok
} 
