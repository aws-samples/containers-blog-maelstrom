FROM python:3-alpine

ENV KUBECONFIG /home/kubectl/.kube/kubeconfig
ENV HOME /home/kubectl

RUN \
	mkdir /root/bin /aws; \
    apk add --update groff less bash py-pip jq curl && \
	pip install --upgrade pip; \
	pip install awscli && \
	apk --purge -v del py-pip && \
	rm /var/cache/apk/* && \
	adduser kubectl -Du 5566

ADD https://amazon-eks.s3-us-west-2.amazonaws.com/1.14.6/2019-08-22/bin/linux/amd64/kubectl /usr/local/bin/kubectl

WORKDIR $HOME

COPY entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod a+x /usr/local/bin/kubectl /usr/local/bin/entrypoint.sh


# USER kubectl
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]