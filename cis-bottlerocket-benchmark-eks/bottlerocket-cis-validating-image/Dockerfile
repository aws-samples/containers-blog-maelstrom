FROM alpine
COPY ./validating-script.sh /
RUN chmod +x /validating-script.sh
RUN apk update && apk add bash && apk add iptables && apk add ip6tables
ENTRYPOINT ["bash", "/validating-script.sh"]