FROM nginx:alpine

# from https://learn.microsoft.com/en-us/azure/app-service/configure-custom-container?tabs=alpine&pivots=container-linux#configure-environment-variables
RUN apk add openrc openssh \
  && ssh-keygen -A \
  && mkdir -p /run/openrc \
  && touch /run/openrc/softlevel \
  && echo "root:Docker!" | chpasswd
COPY ./sshd_config /etc/ssh/sshd_config
COPY ./10-start-sshd.sh /docker-entrypoint.d/10-start-sshd.sh 
