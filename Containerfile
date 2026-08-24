FROM mcr.microsoft.com/dotnet/aspnet:10.0-alpine

RUN apk add --no-cache openssh openssl sudo shadow vim python3 py3-pip bash

RUN python3 -m venv /root/python

RUN ssh-keygen -A

ARG SSH_PUBKEY
RUN mkdir -p /root/.ssh && \
    echo "${SSH_PUBKEY}" > /root/.ssh/authorized_keys && \
    chmod 700 /root/.ssh && \
    chmod 600 /root/.ssh/authorized_keys && \
    chown -R root:root /root/.ssh

RUN sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config && \
    sed -i 's/^#\?Port.*/Port 22/' /etc/ssh/sshd_config && \
    sed -i 's/^#\?AllowTcpForwarding.*/AllowTcpForwarding yes/' /etc/ssh/sshd_config

RUN echo "source /root/python/bin/activate" >> /root/.profile
ENV PATH="/root/python/bin:$PATH"
RUN pip install locust

EXPOSE 22
CMD ["/usr/sbin/sshd", "-D"]
