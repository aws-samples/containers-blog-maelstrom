apiVersion: monitoring.coreos.com/v1alpha1
kind: ScrapeConfig
metadata:
  name: msk-exporters
  namespace: kube-system
  labels:
    release: kube-prometheus-stack
spec:
  staticConfigs:
    - labels:
        job: jmx
      targets:
%{ for broker in brokers ~}
        - "${broker}:11001"
%{ endfor ~}
    - labels:
        job: node-exporter
      targets:
%{ for broker in brokers ~}
        - "${broker}:11002"
%{ endfor ~}
  scrapeInterval: 60s
