FROM debian:bookworm-slim
RUN apt-get -y update && apt-get -y install iptables
RUN update-alternatives --set iptables /usr/sbin/iptables-legacy
RUN update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
COPY ./bootstrap-script.sh /
RUN chmod +x /bootstrap-script.sh
ENTRYPOINT ["/bootstrap-script.sh"]
