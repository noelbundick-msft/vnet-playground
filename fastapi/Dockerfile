FROM python:alpine

# from https://learn.microsoft.com/en-us/azure/app-service/configure-custom-container?tabs=alpine&pivots=container-linux#configure-environment-variables
RUN apk add openrc openssh \
  && ssh-keygen -A \
  && mkdir -p /run/openrc \
  && touch /run/openrc/softlevel \
  && echo "root:Docker!" | chpasswd
COPY ./sshd_config /etc/ssh/sshd_config

COPY ./entrypoint.sh /entrypoint.sh
ENTRYPOINT [ "/entrypoint.sh" ]

# To verify connection to postgres, run this inside an App Service SSH session:
# note: assumes App Service appsettings are correctly configured
# $ source <(cat /proc/1/environ | strings | sed -r 's/(.*)/export \1/g')
# $ psql
RUN apk add postgresql-client

WORKDIR /app
COPY requirements.txt .
RUN python -m pip install -r requirements.txt

COPY . .

CMD ["uvicorn", "main:app", "--host", "0.0.0.0"]
