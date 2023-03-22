FROM alpine
COPY ./bootstrap-script.sh /
RUN chmod +x /bootstrap-script.sh
RUN apk update && apk add bash && apk add iptables && apk add ip6tables
ENTRYPOINT ["/bootstrap-script.sh"]