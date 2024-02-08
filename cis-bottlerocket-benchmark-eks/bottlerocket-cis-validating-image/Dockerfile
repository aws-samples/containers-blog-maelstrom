FROM debian:bookworm-slim
RUN apt-get -y update && apt-get -y install iptables procps kmod
RUN update-alternatives --set iptables /usr/sbin/iptables-legacy
RUN update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
COPY ./validating-script.sh /
RUN chmod +x /validating-script.sh
ENTRYPOINT ["bash", "/validating-script.sh"]