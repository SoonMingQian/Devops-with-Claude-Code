FROM jenkins/jenkins:latest-jdk21
USER root

# Install Docker CLI and Maven
RUN apt-get update && \
    apt-get install -y docker.io maven && \
    rm -rf /var/lib/apt/lists/*

# Install kubectl
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && \
    rm kubectl

# Allow the jenkins user to run Docker commands via the mounted socket
RUN usermod -aG docker jenkins

USER jenkins
