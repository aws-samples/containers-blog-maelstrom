#!/bin/bash

set -e

usage() {
    cat <<EOF
Generate certificate suitable for use with an custom-kube-scheduler webhook service.

This script uses k8s' CertificateSigningRequest API to a generate a
certificate signed by k8s CA suitable for use with custom-kube-scheduler webhook
services. This requires permissions to create and approve CSR. See
https://kubernetes.io/docs/tasks/tls/managing-tls-in-a-cluster for
detailed explanation and additional instructions.

The server key/cert k8s CA cert are stored in a k8s secret.

usage: ${0} [OPTIONS]

The following flags are required.

       --service          Service name of webhook.
       --namespace        Namespace where webhook service and secret reside.
       --secret           Secret name for CA certificate and server certificate/key pair.
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case ${1} in
        --service)
            service="$2"
            shift
            ;;
        --secret)
            secret="$2"
            shift
            ;;
        --namespace)
            namespace="$2"
            shift
            ;;
        *)
            usage
            ;;
    esac
    shift
done

[ -z "${service}" ] && service=custom-kube-scheduler-webhook
[ -z "${secret}" ] && secret=custom-kube-scheduler-webhook-certs
[ -z "${namespace}" ] && namespace=custom-kube-scheduler-webhook

if [ ! -x "$(command -v cfssl)" ]; then
    echo "cfssl not found"
    exit 1
fi

if [ ! -x "$(command -v cfssljson)" ]; then
    echo "cfssljson not found"
    exit 1
fi


csrName=${service}.${namespace}

tmpdir=$(mktemp -d)
echo "creating certs in tmpdir ${tmpdir} "


cat <<EOF | cfssl genkey - | cfssljson -bare server
{
  "hosts": [
    "$service",
    "$service.$namespace",
    "$service.$namespace.svc"
  ],
  "CN": "$service.$namespace.svc",
  "key": {
    "algo": "rsa",
    "size": 2048
  }
}
EOF

mv server.csr ${tmpdir}
mv server-key.pem ${tmpdir}


# clean-up any previously created CSR for our service. Ignore errors if not present.
kubectl delete csr ${csrName} 2>/dev/null || true


# create  server cert/key CSR and  send to k8s API
cat <<EOF | kubectl create -f -
apiVersion: certificates.k8s.io/v1beta1
kind: CertificateSigningRequest
metadata:
  name: ${csrName}
spec:
  groups:
  - system:authenticated
  request: $(cat "${tmpdir}/server.csr"  | base64 | tr -d '\n')
  usages:
  - digital signature
  - key encipherment
  - server auth
EOF



# verify CSR has been created
while true; do
    if kubectl get csr ${csrName}; then
        break
    else
        sleep 1
    fi
done

# approve and fetch the signed certificate
kubectl certificate approve ${csrName}


# verify certificate has been signed
for _ in $(seq 10); do
    serverCert=$(kubectl get csr ${csrName} -o jsonpath='{.status.certificate}')
    if [[ ${serverCert} != '' ]]; then
        break
    fi
    sleep 1
done


if [[ ${serverCert} == '' ]]; then
    echo "ERROR: After approving csr ${csrName}, the signed certificate did not appear on the resource. Giving up after 10 attempts." >&2
    exit 1
fi


kubectl get csr $csrName -o jsonpath='{.status.certificate}' | base64 --decode > "${tmpdir}/server.crt"


# clean-up any previously created CSR for our service. Ignore errors if not present.
kubectl delete secret ${secret} -n ${namespace} 2>/dev/null || true


# create the secret with CA cert and server cert/key
kubectl create secret tls ${secret} --cert "${tmpdir}/server.crt"  --key "${tmpdir}/server-key.pem" -n ${namespace}

