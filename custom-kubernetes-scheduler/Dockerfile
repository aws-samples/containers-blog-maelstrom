FROM alpine:latest

LABEL  name="custom-kube-scheduler-webhook" \
  description="A Kubernetes mutating webhook server that implements custom pod scheduling"

ENV CUSTOM_KUBE_SCHEDULER_WEBHOOK=/usr/local/bin/custom-kube-scheduler-webhook \
  USER_UID=1001 \
  USER_NAME=custom-kube-scheduler-webhook

COPY output/custom-kube-scheduler-webhook ${CUSTOM_KUBE_SCHEDULER_WEBHOOK}

ENTRYPOINT ["/usr/local/bin/custom-kube-scheduler-webhook"]

USER ${USER_UID}
