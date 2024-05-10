FROM golang:1.22.2-bookworm as godeps

# Install custom Terraform Google Workspace provider
# Work around for issues:
# - Password requirement: https://github.com/hashicorp/terraform-provider-googleworkspace/issues/351
# - Timeout issues: https://github.com/hashicorp/terraform-provider-googleworkspace/issues/387
# - Invalid password length restriction (https://github.com/WATonomous/terraform-provider-googleworkspace/commit/c71d1c1a0bed139e0e98b574dbb4609cb3997dd5)
RUN mkdir /opt/terraform-googleworkspace-provider \
    && cd /opt/terraform-googleworkspace-provider \
    && git init \
    && git remote add origin https://github.com/hashicorp/terraform-provider-googleworkspace.git \
    && git fetch origin c71d1c1a0bed139e0e98b574dbb4609cb3997dd5 --depth=1 \
    && git reset --hard FETCH_HEAD \
    && go build -trimpath -ldflags=-buildid= -o /opt/terraform-registry/terraform.local/local/googleworkspace/0.0.1/linux_amd64/terraform-provider-googleworkspace

# Install tfk8s to make working with Kubernetes and Terraform easier
RUN go install github.com/jrhouston/tfk8s@v0.1.10

# Install Terraform
RUN cd /opt \
    && git clone --depth 1 https://github.com/watonomous/terraform --branch 1.8.2-wato-dev \
    && cd terraform \
    && go install .

# Linter for Jsonnet
RUN go install github.com/google/go-jsonnet/cmd/jsonnet-lint@v0.20.0

# Install Terragrunt
RUN cd /opt \
    && git clone --depth 1 https://github.com/watonomous/terragrunt --branch v0.53.8-wato-dev \
    && cd terragrunt \
    && git checkout 685aa0125e3ed40b57dd2d152526b2394c8be9e8 \
    && go install .

FROM bitnami/kubectl:1.26.1 as kubectl

FROM debian:bookworm-20231030-slim

SHELL ["/bin/bash", "-c"]
# We are using docker. To keep things simple we won't use venv
ENV PIP_BREAK_SYSTEM_PACKAGES=1

# Install requirements
RUN apt-get update && apt-get install -y --no-install-recommends git shellcheck rsync tini jq wget sshpass vim openssh-client curl iputils-ping xz-utils python3-pip
COPY requirements.txt .
RUN pip install -r requirements.txt --break-system-packages
# Requirements for the Ceph Terraform provider
RUN apt-get update && apt-get install -y --no-install-recommends libcephfs-dev librbd-dev librados-dev

# Install yq
ARG YQ_VERSION=4.34.1
RUN wget --quiet https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64 -O /usr/bin/yq \
    && echo "7b0fdb1137ae8b80b79610d0046aa42e9a2a7df5eee25dc41ec81a736bb93935ec179b1763b7bcd95af6fa9409d46192f14e85384c165a7c9f70e3159e4dcbae /usr/bin/yq" | sha512sum -c - \
    && chmod +x /usr/bin/yq

# Install nodejs
RUN wget --quiet https://nodejs.org/dist/v20.9.0/node-v20.9.0-linux-x64.tar.xz -O /tmp/node.tar.xz \
    && echo "9033989810bf86220ae46b1381bdcdc6c83a0294869ba2ad39e1061f1e69217a /tmp/node.tar.xz" | sha256sum -c - \
    && tar -xf /tmp/node.tar.xz -C /usr/local --strip-components=1 \
    && rm /tmp/node.tar.xz

# Install nodejs dependencies
RUN npm install -g ajv-cli ajv-formats

# We use Jsonnet to generate JSON schemas
# Install jrsonnet (rust version of Jsonnet) to get the `--exp-preserve-order` feature that we need in JSON schemas (when we use them in forms)
RUN wget --quiet https://github.com/CertainLach/jrsonnet/releases/download/v0.5.0-pre1-test/jrsonnet-linux-gnu-amd64 -O /usr/bin/jrsonnet \
    && echo "588b22d85ce885b93a628a92fee70d9d850dbb1d5d2244c0619b199183022254 /usr/bin/jrsonnet" | sha256sum -c - \
    && chmod +x /usr/bin/jrsonnet

# Install k9s
RUN wget --quiet https://github.com/derailed/k9s/releases/download/v0.31.8/k9s_Linux_amd64.tar.gz -O /tmp/k9s.tar.gz \
    && tar -xf /tmp/k9s.tar.gz -C /usr/local/bin k9s \
    && echo "03dbb615e22a0fd74fe0cd3fc4c5c6d9d6bc9ee9060167017043aec1c62fd698 /usr/local/bin/k9s" | sha256sum -c - \
    && rm /tmp/k9s.tar.gz

# Copy Terraform-related files
COPY --from=godeps /opt/terraform-registry /usr/share/terraform/plugins
# Copy go binaries
RUN mkdir /go
COPY --from=godeps /go/bin /go/bin
# Add go binaries to PATH
# for sh
RUN echo 'export PATH="${PATH}:/go/bin"' >> /etc/profile.d/go-path.sh
# for bash
ENV PATH="${PATH}:/go/bin"

# Install kubectl
COPY --from=kubectl /opt/bitnami/kubectl/bin/kubectl /usr/local/bin/

# This tells /bin/sh to source an environment file on startup
ENV ENV=/etc/profile

# Add "start SSH agent if not started" to the startup script
RUN echo '[ ! -f ~/.ssh-agent-env ] && ssh-agent > ~/.ssh-agent-env; source ~/.ssh-agent-env' >> /etc/profile.d/ssh-agent.sh

# Add a flag to the startup script to indicate that the profile has been initialized
RUN echo 'export PROFILE_INITIALIZED=1' >> /etc/profile.d/profile-initialized.sh

# Because we're running as root, we need to set the umask to 0000
# so that any files created by the container are writable outside
# of the container
RUN echo 'umask 0000' > /etc/profile.d/umask.sh

# Make the root directory writable by any user
RUN chmod 777 /root

# Disable Git safe directory checks, so that we can run Git commands in mounted volumes
RUN echo $'\n\
[safe]\n\
    directory = *\n\
' >> /etc/gitconfig

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["sleep", "infinity"]
